public struct LexOptions: Sendable, Equatable {
  public let debugMode: Bool
  public let runtimeProfile: RuntimeProfile

  public init(debugMode: Bool = false, runtimeProfile: RuntimeProfile = .v0) {
    self.debugMode = debugMode
    self.runtimeProfile = runtimeProfile
  }
}

public struct PageLexResult: Sendable, Equatable {
  public let packedRows: [UInt64]
  public let rowCount: Int32

  public init(packedRows: [UInt64], rowCount: Int32) {
    self.packedRows = packedRows
    self.rowCount = rowCount
  }
}

public func lexPage(
  bytes: [UInt8],
  validLen: Int32,
  baseOffset: Int64,
  artifact: ArtifactRuntime,
  options: LexOptions
) -> PageLexResult {
  let boundedValidLen = max(0, min(Int(validLen), bytes.count))
  guard boundedValidLen > 0 else {
    return PageLexResult(packedRows: [], rowCount: 0)
  }

  let classIDs = classify(bytes: bytes, validLen: boundedValidLen, byteToClassLUT: artifact.byteToClassLUT)

  // Fast-family execution is intentionally stubbed for now.
  let fastWinners: [CandidateWinner] = []

  var integratedWinners = reduceBucketWinners(buckets: [fastWinners])
  if options.runtimeProfile == .v1Fallback, let fallback = artifact.fallback {
    let fallbackRunner = FallbackKernelRunner(fallback: fallback)
    let fallbackResult = fallbackRunner.evaluatePage(classIDs: classIDs, validLen: Int32(boundedValidLen))
    integratedWinners = integrateWithFallback(
      fastWinners: fastWinners,
      fallbackResult: fallbackResult,
      pageWidth: boundedValidLen
    )
  }

  let selected = greedyNonOverlapSelect(winners: integratedWinners, validLen: boundedValidLen)
  let packedRows = selected.map { packRow(winner: $0, baseOffset: baseOffset) }

  return PageLexResult(
    packedRows: packedRows,
    rowCount: Int32(selected.count)
  )
}

private func classify(bytes: [UInt8], validLen: Int, byteToClassLUT: [UInt8]) -> [UInt16] {
  var classIDs = Array(repeating: UInt16(0), count: validLen)
  for i in 0..<validLen {
    let byte = Int(bytes[i])
    if byte >= 0, byte < byteToClassLUT.count {
      classIDs[i] = UInt16(byteToClassLUT[byte])
    }
  }
  return classIDs
}

private func packRow(winner: CandidateWinner, baseOffset: Int64) -> UInt64 {
  let startByte = UInt64(clamping: max(0, Int64(winner.position) + baseOffset))
  let endByte = UInt64(clamping: max(0, Int64(winner.position) + baseOffset + Int64(winner.len)))

  // [63:32]=startByte (low 32 bits), [31:16]=len, [15:8]=mode, [7:0]=token low byte
  let startField = (startByte & 0xFFFF_FFFF) << 32
  let lenField = (UInt64(winner.len) & 0xFFFF) << 16
  let modeField = (UInt64(winner.mode) & 0xFF) << 8
  let tokenField = UInt64(winner.tokenKindID & 0x00FF)
  let packed = startField | lenField | modeField | tokenField

  // Keep `endByte` part of packing decisions even though the current compact format
  // does not store it explicitly.
  _ = endByte
  return packed
}
