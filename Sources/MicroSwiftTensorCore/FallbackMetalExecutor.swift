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

final class FallbackMetalExecutor: @unchecked Sendable {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLComputePipelineState

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

  func evaluate(
    classIDs: [UInt16],
    boundedValidLen: Int,
    fallback: FallbackRuntime
  ) throws -> FallbackPageResult {
    let pageWidth = classIDs.count

    var fallbackLen = Array(repeating: UInt16(0), count: pageWidth)
    var fallbackPriorityRank = Array(repeating: UInt16(0), count: pageWidth)
    var fallbackRuleID = Array(repeating: UInt16(0), count: pageWidth)
    var fallbackTokenKindID = Array(repeating: UInt16(0), count: pageWidth)
    var fallbackMode = Array(repeating: UInt8(0), count: pageWidth)

    guard pageWidth > 0 else {
      return FallbackPageResult(
        fallbackLen: fallbackLen,
        fallbackPriorityRank: fallbackPriorityRank,
        fallbackRuleID: fallbackRuleID,
        fallbackTokenKindID: fallbackTokenKindID,
        fallbackMode: fallbackMode
      )
    }

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

    var config = FallbackKernelConfig(
      validLen: UInt32(boundedValidLen),
      pageWidth: UInt32(pageWidth),
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

    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      throw FallbackMetalExecutorError.commandBufferCreationFailed
    }
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
      throw FallbackMetalExecutorError.commandEncoderCreationFailed
    }

    let classIDsBuffer = try makeBuffer(classIDs, name: "classIDs")
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

    let outLenBuffer = try makeWritableBuffer(UInt16.self, count: pageWidth, name: "outLen")
    let outPriorityBuffer = try makeWritableBuffer(
      UInt16.self, count: pageWidth, name: "outPriorityRank")
    let outRuleIDBuffer = try makeWritableBuffer(UInt16.self, count: pageWidth, name: "outRuleID")
    let outTokenKindBuffer = try makeWritableBuffer(
      UInt16.self, count: pageWidth, name: "outTokenKindID")
    let outModeBuffer = try makeWritableBuffer(UInt8.self, count: pageWidth, name: "outMode")

    encoder.setComputePipelineState(pipelineState)
    encoder.setBuffer(classIDsBuffer, offset: 0, index: 0)
    encoder.setBuffer(stepLoBuffer, offset: 0, index: 1)
    encoder.setBuffer(stepHiBuffer, offset: 0, index: 2)
    encoder.setBuffer(acceptLoBuffer, offset: 0, index: 3)
    encoder.setBuffer(acceptHiBuffer, offset: 0, index: 4)
    encoder.setBuffer(globalRuleIDBuffer, offset: 0, index: 5)
    encoder.setBuffer(priorityRankBuffer, offset: 0, index: 6)
    encoder.setBuffer(tokenKindIDBuffer, offset: 0, index: 7)
    encoder.setBuffer(modeBuffer, offset: 0, index: 8)
    encoder.setBuffer(outLenBuffer, offset: 0, index: 9)
    encoder.setBuffer(outPriorityBuffer, offset: 0, index: 10)
    encoder.setBuffer(outRuleIDBuffer, offset: 0, index: 11)
    encoder.setBuffer(outTokenKindBuffer, offset: 0, index: 12)
    encoder.setBuffer(outModeBuffer, offset: 0, index: 13)
    encoder.setBytes(&config, length: MemoryLayout<FallbackKernelConfig>.stride, index: 14)

    let threadExecutionWidth = max(1, pipelineState.threadExecutionWidth)
    let threadsPerThreadgroup = MTLSize(width: threadExecutionWidth, height: 1, depth: 1)
    let threadsPerGrid = MTLSize(width: pageWidth, height: 1, depth: 1)
    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    guard commandBuffer.status == .completed else {
      throw FallbackMetalExecutorError.backendExecutionFailed(commandBuffer.status)
    }

    fallbackLen = copyArray(UInt16.self, from: outLenBuffer, count: pageWidth)
    fallbackPriorityRank = copyArray(UInt16.self, from: outPriorityBuffer, count: pageWidth)
    fallbackRuleID = copyArray(UInt16.self, from: outRuleIDBuffer, count: pageWidth)
    fallbackTokenKindID = copyArray(UInt16.self, from: outTokenKindBuffer, count: pageWidth)
    fallbackMode = copyArray(UInt8.self, from: outModeBuffer, count: pageWidth)

    return FallbackPageResult(
      fallbackLen: fallbackLen,
      fallbackPriorityRank: fallbackPriorityRank,
      fallbackRuleID: fallbackRuleID,
      fallbackTokenKindID: fallbackTokenKindID,
      fallbackMode: fallbackMode
    )
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
