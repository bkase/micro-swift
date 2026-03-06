/// The pure tensor-core entry point. Implemented in later beads.
public enum TensorLexer {
  public static func lexPage(
    bytes: [UInt8],
    validLen: Int32,
    baseOffset: Int64,
    artifact: ArtifactRuntime,
    options: LexOptions
  ) -> PageLexResult {
    PageLexResult(packedRows: [], rowCount: 0, errorSpans: [], overflowDiagnostic: nil)
  }
}
