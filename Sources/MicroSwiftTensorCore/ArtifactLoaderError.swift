public enum ArtifactLoaderError: Error, Equatable, Sendable {
  case invalidByteToClassSize(expected: Int, got: Int)
  case emptyRules
}
