import MicroSwiftLexerGen

public func validateV0UnderV1Fallback(artifact: LexerArtifact) -> Bool {
  guard !artifact.rules.contains(where: { $0.family == .fallback || $0.family == .localWindow }) else {
    return false
  }

  guard CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback).isEmpty else {
    return false
  }

  guard let runtime = try? ArtifactRuntime.fromArtifact(artifact), runtime.fallback == nil else {
    return false
  }

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

    guard v0 == v1 else {
      return false
    }
  }

  return true
}

private let v0CompatibilitySamples: [[UInt8]] = [
  Array("".utf8),
  Array("func add(x: int) -> int { return x + 1 }".utf8),
  Array("let x = 42 // comment".utf8),
  Array("if true { return false } else { return true }".utf8),
]
