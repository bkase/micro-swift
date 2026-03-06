import Foundation

public struct KernelCacheKey: Hashable, Sendable {
  public let deviceID: String
  public let artifactHash: String
  public let pageBucket: Int
  public let inputDType: String

  public init(deviceID: String, artifactHash: String, pageBucket: Int, inputDType: String) {
    self.deviceID = deviceID
    self.artifactHash = artifactHash
    self.pageBucket = pageBucket
    self.inputDType = inputDType
  }
}

public struct KernelCacheEntry: Sendable {
  public let fallbackRunner: FallbackKernelRunner
  public let createdAt: Date

  public init(fallbackRunner: FallbackKernelRunner, createdAt: Date) {
    self.fallbackRunner = fallbackRunner
    self.createdAt = createdAt
  }
}

public struct KernelCacheLog: Codable, Sendable {
  public let traceID: String
  public let event: String
  public let artifactHash: String
  public let pageBucket: Int
  public let deviceID: String
  public let failureReason: String?

  public init(
    traceID: String,
    event: String,
    artifactHash: String,
    pageBucket: Int,
    deviceID: String,
    failureReason: String? = nil
  ) {
    self.traceID = traceID
    self.event = event
    self.artifactHash = artifactHash
    self.pageBucket = pageBucket
    self.deviceID = deviceID
    self.failureReason = failureReason
  }
}

public actor KernelCache {
  private var entries: [KernelCacheKey: KernelCacheEntry] = [:]
  private let logSink: @Sendable (String) -> Void
  private let jsonEncoder: JSONEncoder

  public init(logSink: @escaping @Sendable (String) -> Void = { _ in }) {
    self.logSink = logSink

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.jsonEncoder = encoder
  }

  public func lookup(key: KernelCacheKey, traceID: String = UUID().uuidString) -> KernelCacheEntry?
  {
    if let entry = entries[key] {
      return entry
    }

    emit(
      KernelCacheLog(
        traceID: traceID,
        event: "fallback-kernel-cache-miss",
        artifactHash: key.artifactHash,
        pageBucket: key.pageBucket,
        deviceID: key.deviceID
      )
    )

    return nil
  }

  public func store(key: KernelCacheKey, entry: KernelCacheEntry) {
    entries[key] = entry
  }

  public func getOrCreate(
    key: KernelCacheKey,
    traceID: String = UUID().uuidString,
    create: () throws -> FallbackKernelRunner
  ) throws -> KernelCacheEntry {
    if let entry = entries[key] {
      return entry
    }

    emit(
      KernelCacheLog(
        traceID: traceID,
        event: "fallback-kernel-cache-miss",
        artifactHash: key.artifactHash,
        pageBucket: key.pageBucket,
        deviceID: key.deviceID
      )
    )

    do {
      let runner = try create()
      let entry = KernelCacheEntry(fallbackRunner: runner, createdAt: Date())
      entries[key] = entry
      return entry
    } catch {
      emit(
        KernelCacheLog(
          traceID: traceID,
          event: "fallback-kernel-cache-create-failure",
          artifactHash: key.artifactHash,
          pageBucket: key.pageBucket,
          deviceID: key.deviceID,
          failureReason: String(describing: error)
        )
      )
      throw error
    }
  }

  private func emit(_ record: KernelCacheLog) {
    guard let data = try? jsonEncoder.encode(record),
      let json = String(data: data, encoding: .utf8)
    else {
      return
    }
    logSink(json)
  }
}
