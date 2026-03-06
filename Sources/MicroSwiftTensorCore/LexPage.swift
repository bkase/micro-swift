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

  let classIDs = classify(
    bytes: bytes, validLen: boundedValidLen, byteToClassLUT: artifact.byteToClassLUT)

  let fastWinners = executeFastFamilies(
    bytes: bytes, classIDs: classIDs, validLen: boundedValidLen, artifact: artifact)

  var integratedWinners = reduceBucketWinners(buckets: [fastWinners])
  if options.runtimeProfile == .v1Fallback, let fallback = artifact.fallback {
    let fallbackRunner = FallbackKernelRunner(fallback: fallback)
    let fallbackResult = fallbackRunner.evaluatePage(
      classIDs: classIDs, validLen: Int32(boundedValidLen))
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

import MicroSwiftLexerGen

func executeFastFamilies(
  bytes: [UInt8],
  classIDs: [UInt16],
  validLen: Int,
  artifact: ArtifactRuntime
) -> [CandidateWinner] {
  var winners: [CandidateWinner] = []

  for rule in artifact.rules {
    switch rule.plan {
    case .literal(let literalBytes):
      for i in 0..<validLen {
        let remaining = validLen - i
        guard remaining >= literalBytes.count else { continue }
        var matched = true
        for j in 0..<literalBytes.count {
          if bytes[i + j] != literalBytes[j] {
            matched = false
            break
          }
        }
        if matched {
          winners.append(CandidateWinner(
            position: i,
            len: UInt16(literalBytes.count),
            priorityRank: rule.priorityRank,
            ruleID: rule.ruleID,
            tokenKindID: rule.tokenKindID,
            mode: modeIDForRule(rule.mode)
          ))
        }
      }

    case .runClassRun(let bodyClassSetID, let minLength):
      let bodyClasses = classSetMembers(classSetID: bodyClassSetID, artifact: artifact)
      for i in 0..<validLen {
        guard bodyClasses.contains(classIDs[i]) else { continue }
        var end = i + 1
        while end < validLen, bodyClasses.contains(classIDs[end]) { end += 1 }
        let runLen = end - i
        if runLen >= Int(minLength) {
          winners.append(CandidateWinner(
            position: i,
            len: UInt16(runLen),
            priorityRank: rule.priorityRank,
            ruleID: rule.ruleID,
            tokenKindID: rule.tokenKindID,
            mode: modeIDForRule(rule.mode)
          ))
        }
      }

    case .runHeadTail(let headClassSetID, let tailClassSetID):
      let headClasses = classSetMembers(classSetID: headClassSetID, artifact: artifact)
      let tailClasses = classSetMembers(classSetID: tailClassSetID, artifact: artifact)
      for i in 0..<validLen {
        guard headClasses.contains(classIDs[i]) else { continue }
        var end = i + 1
        while end < validLen, tailClasses.contains(classIDs[end]) { end += 1 }
        winners.append(CandidateWinner(
          position: i,
          len: UInt16(end - i),
          priorityRank: rule.priorityRank,
          ruleID: rule.ruleID,
          tokenKindID: rule.tokenKindID,
          mode: modeIDForRule(rule.mode)
        ))
      }

    case .runPrefixed(let prefix, let bodyClassSetID, _):
      let bodyClasses = classSetMembers(classSetID: bodyClassSetID, artifact: artifact)
      for i in 0..<validLen {
        let remaining = validLen - i
        guard remaining >= prefix.count else { continue }
        var prefixMatched = true
        for j in 0..<prefix.count {
          if bytes[i + j] != prefix[j] {
            prefixMatched = false
            break
          }
        }
        guard prefixMatched else { continue }
        var end = i + prefix.count
        while end < validLen, bodyClasses.contains(classIDs[end]) { end += 1 }
        winners.append(CandidateWinner(
          position: i,
          len: UInt16(end - i),
          priorityRank: rule.priorityRank,
          ruleID: rule.ruleID,
          tokenKindID: rule.tokenKindID,
          mode: modeIDForRule(rule.mode)
        ))
      }

    case .fallback, .localWindow:
      continue
    }
  }

  return winners
}

private func classSetMembers(classSetID: UInt16, artifact: ArtifactRuntime) -> Set<UInt16> {
  for cs in artifact.classSets {
    if cs.classSetID.rawValue == classSetID {
      return Set(cs.classes.map { UInt16($0) })
    }
  }
  return []
}

private func modeIDForRule(_ mode: RuleMode) -> UInt8 {
  switch mode {
  case .emit: return 0
  case .skip: return 1
  }
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

  // Compact row layout:
  // [63:32]=startByte (low 32 bits), [31:16]=len, [15:0]=tokenKindID.
  // The prior format truncated token kinds to 8 bits in order to carry `mode`,
  // but there is no in-repo packed-row consumer for `mode` and no spare bit left
  // once span and the full 16-bit token kind are preserved.
  let startField = (startByte & 0xFFFF_FFFF) << 32
  let lenField = (UInt64(winner.len) & 0xFFFF) << 16
  let tokenField = UInt64(winner.tokenKindID) & 0xFFFF
  let packed = startField | lenField | tokenField

  // Keep `endByte` part of packing decisions even though the current compact format
  // does not store it explicitly.
  _ = endByte
  _ = winner.mode
  return packed
}
