/// Runtime representation of a loaded lexer artifact.
/// P2 (bd-1i4) will provide the real implementation.
public struct ArtifactRuntime: Sendable {
  public let specName: String
  public let ruleCount: Int

  public init(specName: String, ruleCount: Int) {
    self.specName = specName
    self.ruleCount = ruleCount
  }
}
