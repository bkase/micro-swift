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

    return try ArtifactRuntime.fromArtifact(artifact)
  }
}
