import MicroSwiftLexerGen

public func validateV0UnderV1Fallback(artifact: LexerArtifact) -> Bool {
  guard !artifact.rules.contains(where: { $0.family == .fallback || $0.family == .localWindow })
  else {
    return false
  }

  guard CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback).isEmpty else {
    return false
  }

  guard let runtime = try? ArtifactRuntime.fromArtifact(artifact), runtime.fallback == nil else {
    return false
  }

  var meaningfulSampleCount = 0

  for bytes in v0CompatibilitySamples {
    let v0 = lexPage(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v0)
    )
    let v1 = lexPage(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    let v0Tokens = TokenUnpacker.unpack(result: v0, baseOffset: 0)
    let v1Tokens = TokenUnpacker.unpack(result: v1, baseOffset: 0)

    guard v0Tokens == v1Tokens else {
      return false
    }
    guard v0.errorSpans == v1.errorSpans else {
      return false
    }
    guard v0.overflowDiagnostic == v1.overflowDiagnostic else {
      return false
    }
    guard v0.rowCount == v1.rowCount else {
      return false
    }
    guard v0.hostPackedRows() == v1.hostPackedRows() else {
      return false
    }

    if !v0Tokens.isEmpty || !v0.errorSpans.isEmpty {
      meaningfulSampleCount += 1
    }
  }

  return meaningfulSampleCount > 0
}

private let v0CompatibilitySamples: [[UInt8]] = [
  Array("".utf8),
  Array("func add(x: int) -> int { return x + 1 }".utf8),
  Array("let x = 42 // comment".utf8),
  Array("if true { return false } else { return true }".utf8),
]
