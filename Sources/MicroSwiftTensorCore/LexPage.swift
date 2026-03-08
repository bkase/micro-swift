public func lexPage(
  bytes: [UInt8],
  validLen: Int32,
  baseOffset: Int64,
  artifact: ArtifactRuntime,
  options: LexOptions
) -> PageLexResult {
  TensorLexer.lexPage(
    bytes: bytes,
    validLen: validLen,
    baseOffset: baseOffset,
    artifact: artifact,
    options: options
  )
}
