public struct LexOptions: Sendable, Equatable {
  public let emitSkipTokens: Bool
  public let debugMode: Bool
  public let runtimeProfile: RuntimeProfile
  public let useGPUReduction: Bool

  public init(
    emitSkipTokens: Bool = false,
    debugMode: Bool = false,
    runtimeProfile: RuntimeProfile = .v0,
    useGPUReduction: Bool = false
  ) {
    self.emitSkipTokens = emitSkipTokens
    self.debugMode = debugMode
    self.runtimeProfile = runtimeProfile
    self.useGPUReduction = useGPUReduction
  }
}
