public struct FallbackObservability: Sendable, Equatable {
  public private(set) var fallbackPositionsEntered: Int
  public private(set) var fallbackPositionsSkippedByStartMask: Int
  public private(set) var fallbackCacheMisses: Int
  public private(set) var fallbackCacheHits: Int
  public private(set) var fallbackKernelBackendDispatches: Int

  public init(
    fallbackPositionsEntered: Int = 0,
    fallbackPositionsSkippedByStartMask: Int = 0,
    fallbackCacheMisses: Int = 0,
    fallbackCacheHits: Int = 0,
    fallbackKernelBackendDispatches: Int = 0
  ) {
    self.fallbackPositionsEntered = fallbackPositionsEntered
    self.fallbackPositionsSkippedByStartMask = fallbackPositionsSkippedByStartMask
    self.fallbackCacheMisses = fallbackCacheMisses
    self.fallbackCacheHits = fallbackCacheHits
    self.fallbackKernelBackendDispatches = fallbackKernelBackendDispatches
  }

  public mutating func recordEntered() {
    fallbackPositionsEntered += 1
  }

  public mutating func recordSkippedByStartMask() {
    fallbackPositionsSkippedByStartMask += 1
  }

  public mutating func recordCacheMiss() {
    fallbackCacheMisses += 1
  }

  public mutating func recordCacheHit() {
    fallbackCacheHits += 1
  }

  public mutating func recordKernelBackendDispatch() {
    fallbackKernelBackendDispatches += 1
  }

  public mutating func merge(_ other: FallbackObservability) {
    fallbackPositionsEntered += other.fallbackPositionsEntered
    fallbackPositionsSkippedByStartMask += other.fallbackPositionsSkippedByStartMask
    fallbackCacheMisses += other.fallbackCacheMisses
    fallbackCacheHits += other.fallbackCacheHits
    fallbackKernelBackendDispatches += other.fallbackKernelBackendDispatches
  }
}
