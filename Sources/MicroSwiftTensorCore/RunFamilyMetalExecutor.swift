import Foundation
import Metal

private struct ClassRunConfig {
  var validLen: UInt32
  var pageWidth: UInt32
  var numClassSets: UInt32
  var numByteClasses: UInt32
  var bodySetID: UInt16
  var minLength: UInt16
  var _padding: UInt32
}

private struct HeadTailConfig {
  var validLen: UInt32
  var pageWidth: UInt32
  var numClassSets: UInt32
  var numByteClasses: UInt32
  var headSetID: UInt16
  var tailSetID: UInt16
  var _padding: UInt32
}

private enum RunFamilyMetalExecutorError: Error, CustomStringConvertible {
  case noSystemDevice
  case commandQueueCreationFailed
  case libraryCompilationFailed
  case functionLookupFailed(String)
  case pipelineCreationFailed(String)
  case commandBufferCreationFailed
  case commandEncoderCreationFailed
  case bufferCreationFailed(String)
  case backendExecutionFailed(MTLCommandBufferStatus)

  var description: String {
    switch self {
    case .noSystemDevice: return "MTLCreateSystemDefaultDevice() returned nil"
    case .commandQueueCreationFailed: return "Metal command queue creation failed"
    case .libraryCompilationFailed: return "Metal run-family library compilation failed"
    case .functionLookupFailed(let name): return "Metal function not found: \(name)"
    case .pipelineCreationFailed(let name):
      return "Metal pipeline creation failed for function: \(name)"
    case .commandBufferCreationFailed: return "Metal command buffer creation failed"
    case .commandEncoderCreationFailed: return "Metal command encoder creation failed"
    case .bufferCreationFailed(let name): return "Metal buffer creation failed for \(name)"
    case .backendExecutionFailed(let status):
      return "Metal command buffer finished with status \(status.rawValue)"
    }
  }
}

enum RunFamilyMetalExecutorProvider {
  static let shared: RunFamilyMetalExecutor = {
    do {
      return try RunFamilyMetalExecutor()
    } catch {
      preconditionFailure("Unable to initialize run-family Metal executor: \(error)")
    }
  }()
}

final class RunFamilyMetalExecutor: @unchecked Sendable {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let classRunPipelineState: MTLComputePipelineState
  private let headTailPipelineState: MTLComputePipelineState

  init() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw RunFamilyMetalExecutorError.noSystemDevice
    }
    guard let commandQueue = device.makeCommandQueue() else {
      throw RunFamilyMetalExecutorError.commandQueueCreationFailed
    }

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: runFamilyKernelSource, options: nil)
    } catch {
      throw RunFamilyMetalExecutorError.libraryCompilationFailed
    }

    guard let classRunFunction = library.makeFunction(name: "classRunKernel") else {
      throw RunFamilyMetalExecutorError.functionLookupFailed("classRunKernel")
    }
    guard let headTailFunction = library.makeFunction(name: "headTailKernel") else {
      throw RunFamilyMetalExecutorError.functionLookupFailed("headTailKernel")
    }

    do {
      classRunPipelineState = try device.makeComputePipelineState(function: classRunFunction)
    } catch {
      throw RunFamilyMetalExecutorError.pipelineCreationFailed("classRunKernel")
    }
    do {
      headTailPipelineState = try device.makeComputePipelineState(function: headTailFunction)
    } catch {
      throw RunFamilyMetalExecutorError.pipelineCreationFailed("headTailKernel")
    }

    self.device = device
    self.commandQueue = commandQueue
  }

  var backendName: String {
    "metal-\(device.registryID)"
  }

  func evaluateClassRun(
    classIDs: [UInt8],
    validMask: [Bool],
    bodyClassSetID: UInt16,
    minLength: UInt16,
    classSetRuntime: ClassSetRuntime
  ) throws -> [UInt16] {
    let pageWidth = min(classIDs.count, validMask.count)
    guard pageWidth > 0 else { return [] }

    var candidateLengths = Array(repeating: UInt16(0), count: pageWidth)
    let validLen = UInt32(validMask.prefix { $0 }.count)
    let validMaskBytes = validMask.prefix(pageWidth).map { $0 ? UInt8(1) : UInt8(0) }

    var config = ClassRunConfig(
      validLen: validLen,
      pageWidth: UInt32(pageWidth),
      numClassSets: UInt32(classSetRuntime.numClassSets),
      numByteClasses: UInt32(classSetRuntime.numByteClasses),
      bodySetID: bodyClassSetID,
      minLength: minLength,
      _padding: 0
    )

    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      throw RunFamilyMetalExecutorError.commandBufferCreationFailed
    }
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
      throw RunFamilyMetalExecutorError.commandEncoderCreationFailed
    }

    let classIDBuffer = try makeBuffer(Array(classIDs.prefix(pageWidth)), name: "classIDs")
    let validMaskBuffer = try makeBuffer(validMaskBytes, name: "validMask")
    let classSetMaskBuffer = try makeBuffer(
      classSetRuntime.hostMaskBytes(), name: "classSetMask"
    )
    let outLenBuffer = try makeWritableBuffer(UInt16.self, count: pageWidth, name: "outLen")

    encoder.setComputePipelineState(classRunPipelineState)
    encoder.setBuffer(classIDBuffer, offset: 0, index: 0)
    encoder.setBuffer(validMaskBuffer, offset: 0, index: 1)
    encoder.setBuffer(classSetMaskBuffer, offset: 0, index: 2)
    encoder.setBuffer(outLenBuffer, offset: 0, index: 3)
    encoder.setBytes(&config, length: MemoryLayout<ClassRunConfig>.stride, index: 14)

    dispatch(encoder: encoder, pipelineState: classRunPipelineState, width: pageWidth)
    encoder.endEncoding()

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    guard commandBuffer.status == .completed else {
      throw RunFamilyMetalExecutorError.backendExecutionFailed(commandBuffer.status)
    }

    candidateLengths = copyArray(UInt16.self, from: outLenBuffer, count: pageWidth)
    return candidateLengths
  }

  func evaluateHeadTail(
    classIDs: [UInt8],
    validMask: [Bool],
    headClassSetID: UInt16,
    tailClassSetID: UInt16,
    classSetRuntime: ClassSetRuntime
  ) throws -> [UInt16] {
    let pageWidth = min(classIDs.count, validMask.count)
    guard pageWidth > 0 else { return [] }

    var candidateLengths = Array(repeating: UInt16(0), count: pageWidth)
    let validLen = UInt32(validMask.prefix { $0 }.count)
    let validMaskBytes = validMask.prefix(pageWidth).map { $0 ? UInt8(1) : UInt8(0) }

    var config = HeadTailConfig(
      validLen: validLen,
      pageWidth: UInt32(pageWidth),
      numClassSets: UInt32(classSetRuntime.numClassSets),
      numByteClasses: UInt32(classSetRuntime.numByteClasses),
      headSetID: headClassSetID,
      tailSetID: tailClassSetID,
      _padding: 0
    )

    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      throw RunFamilyMetalExecutorError.commandBufferCreationFailed
    }
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
      throw RunFamilyMetalExecutorError.commandEncoderCreationFailed
    }

    let classIDBuffer = try makeBuffer(Array(classIDs.prefix(pageWidth)), name: "classIDs")
    let validMaskBuffer = try makeBuffer(validMaskBytes, name: "validMask")
    let classSetMaskBuffer = try makeBuffer(
      classSetRuntime.hostMaskBytes(), name: "classSetMask"
    )
    let outLenBuffer = try makeWritableBuffer(UInt16.self, count: pageWidth, name: "outLen")

    encoder.setComputePipelineState(headTailPipelineState)
    encoder.setBuffer(classIDBuffer, offset: 0, index: 0)
    encoder.setBuffer(validMaskBuffer, offset: 0, index: 1)
    encoder.setBuffer(classSetMaskBuffer, offset: 0, index: 2)
    encoder.setBuffer(outLenBuffer, offset: 0, index: 3)
    encoder.setBytes(&config, length: MemoryLayout<HeadTailConfig>.stride, index: 14)

    dispatch(encoder: encoder, pipelineState: headTailPipelineState, width: pageWidth)
    encoder.endEncoding()

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    guard commandBuffer.status == .completed else {
      throw RunFamilyMetalExecutorError.backendExecutionFailed(commandBuffer.status)
    }

    candidateLengths = copyArray(UInt16.self, from: outLenBuffer, count: pageWidth)
    return candidateLengths
  }

  private func dispatch(
    encoder: MTLComputeCommandEncoder,
    pipelineState: MTLComputePipelineState,
    width: Int
  ) {
    let executionWidth = max(1, pipelineState.threadExecutionWidth)
    let threadsPerThreadgroup = MTLSize(width: executionWidth, height: 1, depth: 1)
    let threadsPerGrid = MTLSize(width: width, height: 1, depth: 1)
    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
  }

  private func makeBuffer<T>(_ values: [T], name: String) throws -> MTLBuffer {
    guard !values.isEmpty else {
      guard let buffer = device.makeBuffer(length: MemoryLayout<T>.stride, options: .storageModeShared)
      else {
        throw RunFamilyMetalExecutorError.bufferCreationFailed(name)
      }
      return buffer
    }

    let size = MemoryLayout<T>.stride * values.count
    guard
      let buffer = values.withUnsafeBytes({
        device.makeBuffer(bytes: $0.baseAddress!, length: size, options: .storageModeShared)
      })
    else {
      throw RunFamilyMetalExecutorError.bufferCreationFailed(name)
    }
    return buffer
  }

  private func makeWritableBuffer<T>(_: T.Type, count: Int, name: String) throws -> MTLBuffer {
    let length = max(1, MemoryLayout<T>.stride * count)
    guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
      throw RunFamilyMetalExecutorError.bufferCreationFailed(name)
    }
    return buffer
  }

  private func copyArray<T>(_ type: T.Type, from buffer: MTLBuffer, count: Int) -> [T] {
    guard count > 0 else { return [] }
    let pointer = buffer.contents().bindMemory(to: T.self, capacity: count)
    return Array(UnsafeBufferPointer(start: pointer, count: count))
  }
}

private let runFamilyKernelSource = """
#include <metal_stdlib>
using namespace metal;

struct ClassRunConfig {
  uint validLen;
  uint pageWidth;
  uint numClassSets;
  uint numByteClasses;
  ushort bodySetID;
  ushort minLength;
  uint _padding;
};

struct HeadTailConfig {
  uint validLen;
  uint pageWidth;
  uint numClassSets;
  uint numByteClasses;
  ushort headSetID;
  ushort tailSetID;
  uint _padding;
};

inline bool containsClassSet(
  constant uchar* classSetMask,
  uint numClassSets,
  uint numByteClasses,
  ushort setID,
  uchar classID
) {
  if (setID >= numClassSets) {
    return false;
  }
  if (classID >= numByteClasses) {
    return false;
  }
  uint flat = uint(setID) * numByteClasses + uint(classID);
  return classSetMask[flat] != 0;
}

kernel void classRunKernel(
  device const uchar* classIDs [[buffer(0)]],
  device const uchar* validMask [[buffer(1)]],
  constant uchar* classSetMask [[buffer(2)]],
  device ushort* outLen [[buffer(3)]],
  constant ClassRunConfig& cfg [[buffer(14)]],
  uint gid [[thread_position_in_grid]]
) {
  if (gid >= cfg.pageWidth) {
    return;
  }

  if (gid >= cfg.validLen || validMask[gid] == 0) {
    outLen[gid] = 0;
    return;
  }

  bool inBody = containsClassSet(
    classSetMask, cfg.numClassSets, cfg.numByteClasses, cfg.bodySetID, classIDs[gid]);

  bool prevInBody = false;
  if (gid > 0 && gid - 1 < cfg.validLen && validMask[gid - 1] != 0) {
    prevInBody = containsClassSet(
      classSetMask, cfg.numClassSets, cfg.numByteClasses, cfg.bodySetID, classIDs[gid - 1]);
  }

  bool isStart = inBody && !prevInBody;
  if (!isStart) {
    outLen[gid] = 0;
    return;
  }

  uint length = 1;
  uint cursor = gid + 1;
  while (cursor < cfg.validLen && validMask[cursor] != 0) {
    bool nextInBody = containsClassSet(
      classSetMask, cfg.numClassSets, cfg.numByteClasses, cfg.bodySetID, classIDs[cursor]);
    if (!nextInBody) {
      break;
    }
    length += 1;
    cursor += 1;
  }

  if (length < cfg.minLength) {
    outLen[gid] = 0;
    return;
  }
  outLen[gid] = ushort(min(length, uint(65535)));
}

kernel void headTailKernel(
  device const uchar* classIDs [[buffer(0)]],
  device const uchar* validMask [[buffer(1)]],
  constant uchar* classSetMask [[buffer(2)]],
  device ushort* outLen [[buffer(3)]],
  constant HeadTailConfig& cfg [[buffer(14)]],
  uint gid [[thread_position_in_grid]]
) {
  if (gid >= cfg.pageWidth) {
    return;
  }

  if (gid >= cfg.validLen || validMask[gid] == 0) {
    outLen[gid] = 0;
    return;
  }

  bool isHead = containsClassSet(
    classSetMask, cfg.numClassSets, cfg.numByteClasses, cfg.headSetID, classIDs[gid]);
  bool prevIsTail = false;
  if (gid > 0 && gid - 1 < cfg.validLen && validMask[gid - 1] != 0) {
    prevIsTail = containsClassSet(
      classSetMask, cfg.numClassSets, cfg.numByteClasses, cfg.tailSetID, classIDs[gid - 1]);
  }

  bool startsHere = isHead && !prevIsTail;
  if (!startsHere) {
    outLen[gid] = 0;
    return;
  }

  uint length = 1;
  uint cursor = gid + 1;
  while (cursor < cfg.validLen && validMask[cursor] != 0) {
    bool nextIsTail = containsClassSet(
      classSetMask, cfg.numClassSets, cfg.numByteClasses, cfg.tailSetID, classIDs[cursor]);
    if (!nextIsTail) {
      break;
    }
    length += 1;
    cursor += 1;
  }

  outLen[gid] = ushort(min(length, uint(65535)));
}
"""
