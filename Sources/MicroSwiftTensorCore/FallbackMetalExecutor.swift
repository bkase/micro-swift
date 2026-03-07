import Foundation
import Metal

private struct FallbackKernelConfig {
  var validLen: UInt32
  var pageWidth: UInt32
  var maxWidth: UInt16
  var numStatesUsed: UInt16
  var startMaskLo: UInt64
  var startMaskHi: UInt64
  var startClassMaskLo: UInt64
  var startClassMaskHi: UInt64
  var fallbackRuleCount: UInt32
  var stepStride: UInt32
  var maxClassCount: UInt32
  var _padding: UInt32
}

private enum FallbackMetalExecutorError: Error, CustomStringConvertible {
  case noSystemDevice
  case commandQueueCreationFailed
  case libraryCompilationFailed
  case functionLookupFailed
  case pipelineCreationFailed
  case commandBufferCreationFailed
  case commandEncoderCreationFailed
  case bufferCreationFailed(String)
  case backendExecutionFailed(MTLCommandBufferStatus)

  var description: String {
    switch self {
    case .noSystemDevice: return "MTLCreateSystemDefaultDevice() returned nil"
    case .commandQueueCreationFailed: return "Metal command queue creation failed"
    case .libraryCompilationFailed: return "Metal fallback library compilation failed"
    case .functionLookupFailed: return "fallbackKernel function not found"
    case .pipelineCreationFailed: return "Metal compute pipeline creation failed"
    case .commandBufferCreationFailed: return "Metal command buffer creation failed"
    case .commandEncoderCreationFailed: return "Metal compute encoder creation failed"
    case .bufferCreationFailed(let name): return "Metal buffer creation failed for \(name)"
    case .backendExecutionFailed(let status):
      return "Metal command buffer finished with status \(status.rawValue)"
    }
  }
}

enum FallbackMetalExecutorProvider {
  static let shared: FallbackMetalExecutor = {
    do {
      return try FallbackMetalExecutor()
    } catch {
      preconditionFailure("Unable to initialize fallback Metal executor: \(error)")
    }
  }()
}

final class FallbackMetalCompiledKernel: @unchecked Sendable {
  let fallback: FallbackRuntime
  let metadata: KernelCacheRuntimeMetadata

  fileprivate let pipelineState: MTLComputePipelineState
  fileprivate let stepLoBuffer: MTLBuffer
  fileprivate let stepHiBuffer: MTLBuffer
  fileprivate let acceptLoBuffer: MTLBuffer
  fileprivate let acceptHiBuffer: MTLBuffer
  fileprivate let globalRuleIDBuffer: MTLBuffer
  fileprivate let priorityRankBuffer: MTLBuffer
  fileprivate let tokenKindIDBuffer: MTLBuffer
  fileprivate let modeBuffer: MTLBuffer
  fileprivate let staticConfig: FallbackKernelConfig

  fileprivate init(
    fallback: FallbackRuntime,
    metadata: KernelCacheRuntimeMetadata,
    pipelineState: MTLComputePipelineState,
    stepLoBuffer: MTLBuffer,
    stepHiBuffer: MTLBuffer,
    acceptLoBuffer: MTLBuffer,
    acceptHiBuffer: MTLBuffer,
    globalRuleIDBuffer: MTLBuffer,
    priorityRankBuffer: MTLBuffer,
    tokenKindIDBuffer: MTLBuffer,
    modeBuffer: MTLBuffer,
    staticConfig: FallbackKernelConfig
  ) {
    self.fallback = fallback
    self.metadata = metadata
    self.pipelineState = pipelineState
    self.stepLoBuffer = stepLoBuffer
    self.stepHiBuffer = stepHiBuffer
    self.acceptLoBuffer = acceptLoBuffer
    self.acceptHiBuffer = acceptHiBuffer
    self.globalRuleIDBuffer = globalRuleIDBuffer
    self.priorityRankBuffer = priorityRankBuffer
    self.tokenKindIDBuffer = tokenKindIDBuffer
    self.modeBuffer = modeBuffer
    self.staticConfig = staticConfig
  }
}

final class FallbackMetalExecutor: @unchecked Sendable {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLComputePipelineState

  // Buffer pool: reuse per-page GPU buffers across evaluate calls
  private let executionLock = NSLock()
  private var pooledClassIDsBuffer: MTLBuffer?
  private var pooledOutLenBuffer: MTLBuffer?
  private var pooledOutPriorityBuffer: MTLBuffer?
  private var pooledOutRuleIDBuffer: MTLBuffer?
  private var pooledOutTokenKindBuffer: MTLBuffer?
  private var pooledOutModeBuffer: MTLBuffer?

  init() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw FallbackMetalExecutorError.noSystemDevice
    }
    guard let commandQueue = device.makeCommandQueue() else {
      throw FallbackMetalExecutorError.commandQueueCreationFailed
    }

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: fallbackKernelSource, options: nil)
    } catch {
      throw FallbackMetalExecutorError.libraryCompilationFailed
    }

    guard let function = library.makeFunction(name: "fallbackKernel") else {
      throw FallbackMetalExecutorError.functionLookupFailed
    }

    do {
      pipelineState = try device.makeComputePipelineState(function: function)
    } catch {
      throw FallbackMetalExecutorError.pipelineCreationFailed
    }

    self.device = device
    self.commandQueue = commandQueue
  }

  var cacheDeviceID: String {
    "metal-\(device.registryID)"
  }

  func compileKernel(fallback: FallbackRuntime) throws -> FallbackMetalCompiledKernel {
    let stepLo = fallback.hostStepLo()
    let stepHi = fallback.hostStepHi()
    let acceptLoByRule = fallback.hostAcceptLoByRule()
    let acceptHiByRule = fallback.hostAcceptHiByRule()
    let globalRuleIDByFallbackRule = fallback.hostGlobalRuleIDByFallbackRule()
    let priorityRankByFallbackRule = fallback.hostPriorityRankByFallbackRule()
    let tokenKindIDByFallbackRule = fallback.hostTokenKindIDByFallbackRule()
    let modeByFallbackRule = fallback.hostModeByFallbackRule()

    let stepStride = UInt32(max(1, Int(fallback.numStatesUsed)))
    let maxClassCount = UInt32(stepLo.count / Int(stepStride))

    let stepLoBuffer = try makeBuffer(stepLo, name: "stepLo")
    let stepHiBuffer = try makeBuffer(stepHi, name: "stepHi")
    let acceptLoBuffer = try makeBuffer(acceptLoByRule, name: "acceptLoByRule")
    let acceptHiBuffer = try makeBuffer(acceptHiByRule, name: "acceptHiByRule")
    let globalRuleIDBuffer = try makeBuffer(
      globalRuleIDByFallbackRule, name: "globalRuleIDByFallbackRule")
    let priorityRankBuffer = try makeBuffer(
      priorityRankByFallbackRule, name: "priorityRankByFallbackRule")
    let tokenKindIDBuffer = try makeBuffer(
      tokenKindIDByFallbackRule, name: "tokenKindIDByFallbackRule")
    let modeBuffer = try makeBuffer(modeByFallbackRule, name: "modeByFallbackRule")

    let constantTableByteCount =
      stepLoBuffer.length
      + stepHiBuffer.length
      + acceptLoBuffer.length
      + acceptHiBuffer.length
      + globalRuleIDBuffer.length
      + priorityRankBuffer.length
      + tokenKindIDBuffer.length
      + modeBuffer.length

    let metadata = KernelCacheRuntimeMetadata(
      backend: "metal",
      deviceID: cacheDeviceID,
      pipelineFunction: "fallbackKernel",
      constantTableByteCount: constantTableByteCount,
      fallbackRuleCount: globalRuleIDByFallbackRule.count,
      stepStride: Int(stepStride),
      maxClassCount: Int(maxClassCount)
    )

    let staticConfig = FallbackKernelConfig(
      validLen: 0,
      pageWidth: 0,
      maxWidth: fallback.maxWidth,
      numStatesUsed: fallback.numStatesUsed,
      startMaskLo: fallback.startMaskLo,
      startMaskHi: fallback.startMaskHi,
      startClassMaskLo: fallback.startClassMaskLo,
      startClassMaskHi: fallback.startClassMaskHi,
      fallbackRuleCount: UInt32(globalRuleIDByFallbackRule.count),
      stepStride: stepStride,
      maxClassCount: maxClassCount,
      _padding: 0
    )

    return FallbackMetalCompiledKernel(
      fallback: fallback,
      metadata: metadata,
      pipelineState: pipelineState,
      stepLoBuffer: stepLoBuffer,
      stepHiBuffer: stepHiBuffer,
      acceptLoBuffer: acceptLoBuffer,
      acceptHiBuffer: acceptHiBuffer,
      globalRuleIDBuffer: globalRuleIDBuffer,
      priorityRankBuffer: priorityRankBuffer,
      tokenKindIDBuffer: tokenKindIDBuffer,
      modeBuffer: modeBuffer,
      staticConfig: staticConfig
    )
  }

  func evaluate(
    classIDs: [UInt16],
    boundedValidLen: Int,
    compiledKernel: FallbackMetalCompiledKernel
  ) throws -> FallbackPageResult {
    let pageWidth = classIDs.count

    guard pageWidth > 0 else {
      return FallbackPageResult(
        fallbackLen: Array(repeating: 0, count: pageWidth),
        fallbackPriorityRank: Array(repeating: 0, count: pageWidth),
        fallbackRuleID: Array(repeating: 0, count: pageWidth),
        fallbackTokenKindID: Array(repeating: 0, count: pageWidth),
        fallbackMode: Array(repeating: 0, count: pageWidth)
      )
    }

    executionLock.lock()
    defer { executionLock.unlock() }

    // Ensure pooled buffers have sufficient capacity, reallocating only when needed
    let classIDsByteCount = pageWidth * MemoryLayout<UInt16>.stride
    let outU16ByteCount = pageWidth * MemoryLayout<UInt16>.stride
    let outU8ByteCount = pageWidth * MemoryLayout<UInt8>.stride

    pooledClassIDsBuffer = try ensureBuffer(
      pooledClassIDsBuffer, minBytes: classIDsByteCount, name: "classIDs")
    pooledOutLenBuffer = try ensureBuffer(
      pooledOutLenBuffer, minBytes: outU16ByteCount, name: "outLen")
    pooledOutPriorityBuffer = try ensureBuffer(
      pooledOutPriorityBuffer, minBytes: outU16ByteCount, name: "outPriorityRank")
    pooledOutRuleIDBuffer = try ensureBuffer(
      pooledOutRuleIDBuffer, minBytes: outU16ByteCount, name: "outRuleID")
    pooledOutTokenKindBuffer = try ensureBuffer(
      pooledOutTokenKindBuffer, minBytes: outU16ByteCount, name: "outTokenKindID")
    pooledOutModeBuffer = try ensureBuffer(
      pooledOutModeBuffer, minBytes: outU8ByteCount, name: "outMode")

    // Copy input data into pooled buffer
    classIDs.withUnsafeBytes { bytes in
      pooledClassIDsBuffer!.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
    }

    // Zero output buffers
    memset(pooledOutLenBuffer!.contents(), 0, outU16ByteCount)
    memset(pooledOutPriorityBuffer!.contents(), 0, outU16ByteCount)
    memset(pooledOutRuleIDBuffer!.contents(), 0, outU16ByteCount)
    memset(pooledOutTokenKindBuffer!.contents(), 0, outU16ByteCount)
    memset(pooledOutModeBuffer!.contents(), 0, outU8ByteCount)

    var config = compiledKernel.staticConfig
    config.validLen = UInt32(boundedValidLen)
    config.pageWidth = UInt32(pageWidth)

    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      throw FallbackMetalExecutorError.commandBufferCreationFailed
    }
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
      throw FallbackMetalExecutorError.commandEncoderCreationFailed
    }

    encoder.setComputePipelineState(compiledKernel.pipelineState)
    encoder.setBuffer(pooledClassIDsBuffer!, offset: 0, index: 0)
    encoder.setBuffer(compiledKernel.stepLoBuffer, offset: 0, index: 1)
    encoder.setBuffer(compiledKernel.stepHiBuffer, offset: 0, index: 2)
    encoder.setBuffer(compiledKernel.acceptLoBuffer, offset: 0, index: 3)
    encoder.setBuffer(compiledKernel.acceptHiBuffer, offset: 0, index: 4)
    encoder.setBuffer(compiledKernel.globalRuleIDBuffer, offset: 0, index: 5)
    encoder.setBuffer(compiledKernel.priorityRankBuffer, offset: 0, index: 6)
    encoder.setBuffer(compiledKernel.tokenKindIDBuffer, offset: 0, index: 7)
    encoder.setBuffer(compiledKernel.modeBuffer, offset: 0, index: 8)
    encoder.setBuffer(pooledOutLenBuffer!, offset: 0, index: 9)
    encoder.setBuffer(pooledOutPriorityBuffer!, offset: 0, index: 10)
    encoder.setBuffer(pooledOutRuleIDBuffer!, offset: 0, index: 11)
    encoder.setBuffer(pooledOutTokenKindBuffer!, offset: 0, index: 12)
    encoder.setBuffer(pooledOutModeBuffer!, offset: 0, index: 13)
    encoder.setBytes(&config, length: MemoryLayout<FallbackKernelConfig>.stride, index: 14)

    let threadExecutionWidth = max(1, compiledKernel.pipelineState.threadExecutionWidth)
    let threadsPerThreadgroup = MTLSize(width: threadExecutionWidth, height: 1, depth: 1)
    let threadsPerGrid = MTLSize(width: pageWidth, height: 1, depth: 1)
    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    guard commandBuffer.status == .completed else {
      throw FallbackMetalExecutorError.backendExecutionFailed(commandBuffer.status)
    }

    let fallbackLen = copyArray(UInt16.self, from: pooledOutLenBuffer!, count: pageWidth)
    let fallbackPriorityRank = copyArray(
      UInt16.self, from: pooledOutPriorityBuffer!, count: pageWidth)
    let fallbackRuleID = copyArray(UInt16.self, from: pooledOutRuleIDBuffer!, count: pageWidth)
    let fallbackTokenKindID = copyArray(
      UInt16.self, from: pooledOutTokenKindBuffer!, count: pageWidth)
    let fallbackMode = copyArray(UInt8.self, from: pooledOutModeBuffer!, count: pageWidth)

    return FallbackPageResult(
      fallbackLen: fallbackLen,
      fallbackPriorityRank: fallbackPriorityRank,
      fallbackRuleID: fallbackRuleID,
      fallbackTokenKindID: fallbackTokenKindID,
      fallbackMode: fallbackMode
    )
  }

  private func ensureBuffer(
    _ existing: MTLBuffer?, minBytes: Int, name: String
  ) throws -> MTLBuffer {
    let needed = max(1, minBytes)
    if let buffer = existing, buffer.length >= needed { return buffer }
    guard let buffer = device.makeBuffer(length: needed, options: .storageModeShared) else {
      throw FallbackMetalExecutorError.bufferCreationFailed(name)
    }
    return buffer
  }

  private func makeBuffer<T>(_ values: [T], name: String) throws -> MTLBuffer {
    let length = max(1, values.count * MemoryLayout<T>.stride)
    guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
      throw FallbackMetalExecutorError.bufferCreationFailed(name)
    }

    if !values.isEmpty {
      values.withUnsafeBytes { bytes in
        let destination = buffer.contents()
        destination.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
      }
    }

    return buffer
  }

  private func makeWritableBuffer<T>(_: T.Type, count: Int, name: String) throws -> MTLBuffer {
    let length = max(1, count * MemoryLayout<T>.stride)
    guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
      throw FallbackMetalExecutorError.bufferCreationFailed(name)
    }
    memset(buffer.contents(), 0, length)
    return buffer
  }

  private func copyArray<T>(_ type: T.Type, from buffer: MTLBuffer, count: Int) -> [T] {
    guard count > 0 else { return [] }
    let pointer = buffer.contents().bindMemory(to: T.self, capacity: count)
    let unsafeBuffer = UnsafeBufferPointer(start: pointer, count: count)
    return Array(unsafeBuffer)
  }
}

private let fallbackKernelSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct FallbackKernelConfig {
    uint validLen;
    uint pageWidth;
    ushort maxWidth;
    ushort numStatesUsed;
    ulong startMaskLo;
    ulong startMaskHi;
    ulong startClassMaskLo;
    ulong startClassMaskHi;
    uint fallbackRuleCount;
    uint stepStride;
    uint maxClassCount;
    uint padding;
  };

  inline bool isStartEligible(ushort classID, constant FallbackKernelConfig& cfg) {
    if (classID < 64) {
      ulong mask = 1ul << (ulong)classID;
      return (cfg.startClassMaskLo & mask) != 0ul;
    }

    if (classID < 128) {
      ulong mask = 1ul << (ulong)(classID - 64);
      return (cfg.startClassMaskHi & mask) != 0ul;
    }

    return false;
  }

  kernel void fallbackKernel(
    device const ushort* classIDs [[buffer(0)]],
    constant ulong* stepLo [[buffer(1)]],
    constant ulong* stepHi [[buffer(2)]],
    constant ulong* acceptLoByRule [[buffer(3)]],
    constant ulong* acceptHiByRule [[buffer(4)]],
    constant ushort* globalRuleIDByFallbackRule [[buffer(5)]],
    constant ushort* priorityRankByFallbackRule [[buffer(6)]],
    constant ushort* tokenKindIDByFallbackRule [[buffer(7)]],
    constant uchar* modeByFallbackRule [[buffer(8)]],
    device ushort* outLen [[buffer(9)]],
    device ushort* outPriorityRank [[buffer(10)]],
    device ushort* outRuleID [[buffer(11)]],
    device ushort* outTokenKindID [[buffer(12)]],
    device uchar* outMode [[buffer(13)]],
    constant FallbackKernelConfig& cfg [[buffer(14)]],
    uint gid [[thread_position_in_grid]]
  ) {
    if (gid >= cfg.pageWidth) {
      return;
    }

    ushort bestLen = 0;
    ushort bestPriorityRank = 0;
    ushort bestRuleID = 0;
    ushort bestTokenKindID = 0;
    uchar bestMode = 0;

    if (gid < cfg.validLen && isStartEligible(classIDs[gid], cfg)) {
      ulong activeLo = cfg.startMaskLo;
      ulong activeHi = cfg.startMaskHi;

      for (uint k = 0; k < (uint)cfg.maxWidth; ++k) {
        uint cursor = gid + k;
        if (cursor >= cfg.validLen) {
          activeLo = 0ul;
          activeHi = 0ul;
          continue;
        }

        if (activeLo == 0ul && activeHi == 0ul) {
          continue;
        }

        uint classID = (uint)classIDs[cursor];
        if (classID >= cfg.maxClassCount) {
          activeLo = 0ul;
          activeHi = 0ul;
          continue;
        }

        ulong nextLo = 0ul;
        ulong nextHi = 0ul;

        ulong loBits = activeLo;
        while (loBits != 0ul) {
          uint bit = ctz(loBits);
          uint state = bit;
          if (state < (uint)cfg.numStatesUsed) {
            uint flatIndex = classID * cfg.stepStride + state;
            nextLo |= stepLo[flatIndex];
            nextHi |= stepHi[flatIndex];
          }
          loBits &= (loBits - 1ul);
        }

        ulong hiBits = activeHi;
        while (hiBits != 0ul) {
          uint bit = ctz(hiBits);
          uint state = 64u + bit;
          if (state < (uint)cfg.numStatesUsed) {
            uint flatIndex = classID * cfg.stepStride + state;
            nextLo |= stepLo[flatIndex];
            nextHi |= stepHi[flatIndex];
          }
          hiBits &= (hiBits - 1ul);
        }

        activeLo = nextLo;
        activeHi = nextHi;

        if (activeLo == 0ul && activeHi == 0ul) {
          continue;
        }

        ushort candidateLen = (ushort)(k + 1u);
        for (uint ruleIndex = 0; ruleIndex < cfg.fallbackRuleCount; ++ruleIndex) {
          if ((activeLo & acceptLoByRule[ruleIndex]) == 0ul &&
              (activeHi & acceptHiByRule[ruleIndex]) == 0ul) {
            continue;
          }

          ushort candidatePriority = priorityRankByFallbackRule[ruleIndex];
          ushort candidateRuleID = globalRuleIDByFallbackRule[ruleIndex];

          bool better = false;
          if (candidateLen != bestLen) {
            better = candidateLen > bestLen;
          } else if (candidateLen != 0u) {
            if (candidatePriority != bestPriorityRank) {
              better = candidatePriority < bestPriorityRank;
            } else {
              better = candidateRuleID < bestRuleID;
            }
          }

          if (better) {
            bestLen = candidateLen;
            bestPriorityRank = candidatePriority;
            bestRuleID = candidateRuleID;
            bestTokenKindID = tokenKindIDByFallbackRule[ruleIndex];
            bestMode = modeByFallbackRule[ruleIndex];
          }
        }
      }
    }

    outLen[gid] = bestLen;
    outPriorityRank[gid] = bestPriorityRank;
    outRuleID[gid] = bestRuleID;
    outTokenKindID[gid] = bestTokenKindID;
    outMode[gid] = bestMode;
  }
  """
