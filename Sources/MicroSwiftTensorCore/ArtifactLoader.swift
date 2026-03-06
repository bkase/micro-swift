import MicroSwiftLexerGen

public enum ArtifactLoader {
  /// Load a LexerArtifact into runtime form.
  /// Validates format and extracts runtime constants.
  public static func load(_ artifact: LexerArtifact) throws -> ArtifactRuntime {
    guard artifact.byteToClass.count == 256 else {
      throw ArtifactLoaderError.invalidByteToClassSize(
        expected: 256,
        got: artifact.byteToClass.count
      )
    }

    guard !artifact.rules.isEmpty else {
      throw ArtifactLoaderError.emptyRules
    }

    return ArtifactRuntime(
      specName: artifact.specName,
      ruleCount: artifact.rules.count,
      maxLiteralLength: artifact.runtimeHints.maxLiteralLength,
      maxBoundedRuleWidth: artifact.runtimeHints.maxBoundedRuleWidth,
      maxDeterministicLookaheadBytes: artifact.runtimeHints.maxDeterministicLookaheadBytes,
      byteToClassLUT: artifact.byteToClass,
      tokenKinds: artifact.tokenKinds,
      rules: artifact.rules,
      keywordRemaps: artifact.keywordRemaps,
      classSets: artifact.classSets,
      classes: artifact.classes
    )
  }
}
