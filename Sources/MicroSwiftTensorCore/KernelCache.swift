import Foundation

public struct KernelCacheKey: Hashable, Sendable {
  public let deviceID: String
  public let artifactHash: String
  public let pageBucket: Int
  public let inputDType: String
  public let runtimeProfile: String
  public let layoutSignature: String

  public init(
    deviceID: String,
    artifactHash: String,
    pageBucket: Int,
    inputDType: String,
    runtimeProfile: String = "v1-fallback",
    layoutSignature: String = "v1"
  ) {
    self.deviceID = deviceID
    self.artifactHash = artifactHash
    self.pageBucket = pageBucket
    self.inputDType = inputDType
    self.runtimeProfile = runtimeProfile
    self.layoutSignature = layoutSignature
  }
}

public struct KernelCacheRuntimeMetadata: Codable, Sendable, Equatable {
  public let backend: String
  public let deviceID: String
  public let pipelineFunction: String
  public let constantTableByteCount: Int
  public let fallbackRuleCount: Int
  public let stepStride: Int
  public let maxClassCount: Int

  public init(
    backend: String,
    deviceID: String,
    pipelineFunction: String,
    constantTableByteCount: Int,
    fallbackRuleCount: Int,
    stepStride: Int,
    maxClassCount: Int
  ) {
    self.backend = backend
    self.deviceID = deviceID
    self.pipelineFunction = pipelineFunction
    self.constantTableByteCount = constantTableByteCount
    self.fallbackRuleCount = fallbackRuleCount
    self.stepStride = stepStride
    self.maxClassCount = maxClassCount
  }
}

public struct KernelCacheEntry: Sendable {
  public let fallbackRunner: FallbackKernelRunner?
  public let fastPathGraph: FastPathCompiledGraph?
  public let runtimeMetadata: KernelCacheRuntimeMetadata
  public let createdAt: Date

  public init(
    fallbackRunner: FallbackKernelRunner? = nil,
    fastPathGraph: FastPathCompiledGraph? = nil,
    runtimeMetadata: KernelCacheRuntimeMetadata,
    createdAt: Date
  ) {
    precondition(
      fallbackRunner != nil || fastPathGraph != nil,
      "KernelCacheEntry requires at least one runtime resource"
    )
    self.fallbackRunner = fallbackRunner
    self.fastPathGraph = fastPathGraph
    self.runtimeMetadata = runtimeMetadata
    self.createdAt = createdAt
  }
}

public struct KernelCacheLog: Codable, Sendable, Equatable {
  public let traceID: String
  public let event: String
  public let artifactHash: String
  public let pageBucket: Int
  public let deviceID: String
  public let inputDType: String
  public let runtimeProfile: String
  public let layoutSignature: String
  public let runtimeMetadata: KernelCacheRuntimeMetadata?
  public let failureReason: String?

  public init(
    traceID: String,
    event: String,
    artifactHash: String,
    pageBucket: Int,
    deviceID: String,
    inputDType: String,
    runtimeProfile: String,
    layoutSignature: String,
    runtimeMetadata: KernelCacheRuntimeMetadata? = nil,
    failureReason: String? = nil
  ) {
    self.traceID = traceID
    self.event = event
    self.artifactHash = artifactHash
    self.pageBucket = pageBucket
    self.deviceID = deviceID
    self.inputDType = inputDType
    self.runtimeProfile = runtimeProfile
    self.layoutSignature = layoutSignature
    self.runtimeMetadata = runtimeMetadata
    self.failureReason = failureReason
  }
}

public final class KernelCache: @unchecked Sendable {
  private var entries: [KernelCacheKey: KernelCacheEntry] = [:]
  private let lock = NSLock()
  private let eventPrefix: String
  private let logSink: @Sendable (String) -> Void
  private let jsonEncoder: JSONEncoder

  public init(
    eventPrefix: String = "fallback-kernel-cache",
    logSink: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.eventPrefix = eventPrefix
    self.logSink = logSink

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.jsonEncoder = encoder
  }

  public func lookup(key: KernelCacheKey, traceID: String = UUID().uuidString) -> KernelCacheEntry?
  {
    lock.lock()
    defer { lock.unlock() }

    if let entry = entries[key] {
      emitLocked(
        KernelCacheLog(
          traceID: traceID,
          event: "\(eventPrefix)-hit",
          artifactHash: key.artifactHash,
          pageBucket: key.pageBucket,
          deviceID: key.deviceID,
          inputDType: key.inputDType,
          runtimeProfile: key.runtimeProfile,
          layoutSignature: key.layoutSignature,
          runtimeMetadata: entry.runtimeMetadata
        ))
      return entry
    }

    emitLocked(
      KernelCacheLog(
        traceID: traceID,
        event: "\(eventPrefix)-miss",
        artifactHash: key.artifactHash,
        pageBucket: key.pageBucket,
        deviceID: key.deviceID,
        inputDType: key.inputDType,
        runtimeProfile: key.runtimeProfile,
        layoutSignature: key.layoutSignature
      ))

    return nil
  }

  public func store(
    key: KernelCacheKey, entry: KernelCacheEntry, traceID: String = UUID().uuidString
  ) {
    lock.lock()
    defer { lock.unlock() }

    entries[key] = entry
    emitLocked(
      KernelCacheLog(
        traceID: traceID,
        event: "\(eventPrefix)-store",
        artifactHash: key.artifactHash,
        pageBucket: key.pageBucket,
        deviceID: key.deviceID,
        inputDType: key.inputDType,
        runtimeProfile: key.runtimeProfile,
        layoutSignature: key.layoutSignature,
        runtimeMetadata: entry.runtimeMetadata
      ))
  }

  public func getOrCreate(
    key: KernelCacheKey,
    traceID: String = UUID().uuidString,
    create: () throws -> KernelCacheEntry
  ) throws -> KernelCacheEntry {
    lock.lock()
    if let entry = entries[key] {
      emitLocked(
        KernelCacheLog(
          traceID: traceID,
          event: "\(eventPrefix)-hit",
          artifactHash: key.artifactHash,
          pageBucket: key.pageBucket,
          deviceID: key.deviceID,
          inputDType: key.inputDType,
          runtimeProfile: key.runtimeProfile,
          layoutSignature: key.layoutSignature,
          runtimeMetadata: entry.runtimeMetadata
        ))
      lock.unlock()
      return entry
    }

    emitLocked(
      KernelCacheLog(
        traceID: traceID,
        event: "\(eventPrefix)-miss",
        artifactHash: key.artifactHash,
        pageBucket: key.pageBucket,
        deviceID: key.deviceID,
        inputDType: key.inputDType,
        runtimeProfile: key.runtimeProfile,
        layoutSignature: key.layoutSignature
      ))
    lock.unlock()

    do {
      let entry = try create()

      lock.lock()
      entries[key] = entry
      emitLocked(
        KernelCacheLog(
          traceID: traceID,
          event: "\(eventPrefix)-store",
          artifactHash: key.artifactHash,
          pageBucket: key.pageBucket,
          deviceID: key.deviceID,
          inputDType: key.inputDType,
          runtimeProfile: key.runtimeProfile,
          layoutSignature: key.layoutSignature,
          runtimeMetadata: entry.runtimeMetadata
        ))
      lock.unlock()
      return entry
    } catch {
      lock.lock()
      emitLocked(
        KernelCacheLog(
          traceID: traceID,
          event: "\(eventPrefix)-create-failure",
          artifactHash: key.artifactHash,
          pageBucket: key.pageBucket,
          deviceID: key.deviceID,
          inputDType: key.inputDType,
          runtimeProfile: key.runtimeProfile,
          layoutSignature: key.layoutSignature,
          failureReason: String(describing: error)
        ))
      lock.unlock()
      throw error
    }
  }

  private func emitLocked(_ record: KernelCacheLog) {
    guard let data = try? jsonEncoder.encode(record),
      let json = String(data: data, encoding: .utf8)
    else {
      return
    }
    logSink(json)
  }

  public func clear() {
    lock.lock()
    entries.removeAll(keepingCapacity: true)
    lock.unlock()
  }
}
