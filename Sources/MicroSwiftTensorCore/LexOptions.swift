public struct LexOptions: Sendable {
  public let emitSkipTokens: Bool

  public init(emitSkipTokens: Bool = false) {
    self.emitSkipTokens = emitSkipTokens
  }
}
