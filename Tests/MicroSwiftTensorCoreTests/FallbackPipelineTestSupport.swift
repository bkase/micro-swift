import Foundation

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

struct TestToken: Equatable {
  let start: Int
  let end: Int
  let ruleID: UInt16
  let tokenKindID: UInt16
  let mode: UInt8
  let lexeme: String
}

struct TestErrorRun: Equatable {
  let start: Int
  let end: Int
  let lexeme: String
}

struct TestPipelineResult: Equatable {
  let selected: [CandidateWinner]
  let tokens: [TestToken]
  let errorRuns: [TestErrorRun]
}

func runTestPipeline(
  bytes: [UInt8],
  artifact: LexerArtifact,
  applyKeywordRemap: Bool = true
) throws -> TestPipelineResult {
  let boundedArtifact = makeBoundedFallbackArtifactForTests(artifact)
  let runtime = try ArtifactRuntime.fromArtifact(boundedArtifact)
  let classIDs = bytes.map { UInt16(boundedArtifact.byteToClass[Int($0)]) }

  let fastWinners = buildFastWinners(
    bytes: bytes,
    validLen: bytes.count,
    artifact: boundedArtifact
  )

  let fallbackResult: FallbackPageResult
  if let fallback = runtime.fallback {
    let runner = FallbackKernelRunner(fallback: fallback)
    fallbackResult = runner.evaluatePage(classIDs: classIDs, validLen: Int32(bytes.count))
  } else {
    fallbackResult = FallbackPageResult(
      fallbackLen: Array(repeating: 0, count: bytes.count),
      fallbackPriorityRank: Array(repeating: 0, count: bytes.count),
      fallbackRuleID: Array(repeating: 0, count: bytes.count),
      fallbackTokenKindID: Array(repeating: 0, count: bytes.count),
      fallbackMode: Array(repeating: 0, count: bytes.count)
    )
  }

  let integrated = integrateWithFallback(
    fastWinners: fastWinners,
    fallbackResult: fallbackResult,
    pageWidth: bytes.count
  )
  let selected = greedyNonOverlapSelect(winners: integrated, validLen: bytes.count)

  let coverage = buildCoverageMask(selected: selected, validLen: bytes.count)
  let errorRuns = buildErrorRuns(bytes: bytes, coverage: coverage)
  let tokens = selected.map { winner in
    let start = winner.position
    let len = Int(winner.len)
    let end = min(bytes.count, start + len)
    let lexemeBytes = Array(bytes[start..<end])
    let tokenKindID =
      applyKeywordRemap
      ? remapTokenKind(
        winner: winner,
        lexemeBytes: lexemeBytes,
        artifact: boundedArtifact
      ) : winner.tokenKindID
    return TestToken(
      start: start,
      end: end,
      ruleID: winner.ruleID,
      tokenKindID: tokenKindID,
      mode: winner.mode,
      lexeme: String(decoding: lexemeBytes, as: UTF8.self)
    )
  }

  return TestPipelineResult(selected: selected, tokens: tokens, errorRuns: errorRuns)
}

func renderSnapshot(_ result: TestPipelineResult) -> String {
  var lines: [String] = []
  for token in result.tokens {
    lines.append(
      "TOK[\(token.start)..<\(token.end)] rule=\(token.ruleID) kind=\(token.tokenKindID) mode=\(token.mode) lexeme='\(token.lexeme)'"
    )
  }
  for run in result.errorRuns {
    lines.append("ERR[\(run.start)..<\(run.end)] lexeme='\(run.lexeme)'")
  }
  return lines.joined(separator: "\n")
}

func makeBoundedFallbackArtifactForTests(_ artifact: LexerArtifact) -> LexerArtifact {
  var rules: [LoweredRule] = []
  rules.reserveCapacity(artifact.rules.count)

  var maxWidth: UInt16 = artifact.runtimeHints.maxBoundedRuleWidth

  for rule in artifact.rules {
    guard case .fallback = rule.plan else {
      rules.append(rule)
      continue
    }

    let boundedWidth = rule.maxWidth ?? UInt16(32)
    maxWidth = max(maxWidth, boundedWidth)

    rules.append(
      LoweredRule(
        ruleID: rule.ruleID,
        name: rule.name,
        tokenKindID: rule.tokenKindID,
        mode: rule.mode,
        family: rule.family,
        priorityRank: rule.priorityRank,
        minWidth: rule.minWidth,
        maxWidth: boundedWidth,
        firstClassSetID: rule.firstClassSetID,
        plan: rule.plan
      ))
  }

  return LexerArtifact(
    formatVersion: artifact.formatVersion,
    specName: artifact.specName,
    specHashHex: artifact.specHashHex,
    generatorVersion: artifact.generatorVersion,
    runtimeHints: RuntimeHints(
      maxLiteralLength: artifact.runtimeHints.maxLiteralLength,
      maxBoundedRuleWidth: maxWidth,
      maxDeterministicLookaheadBytes: max(
        artifact.runtimeHints.maxDeterministicLookaheadBytes,
        maxWidth
      )
    ),
    tokenKinds: artifact.tokenKinds,
    byteToClass: artifact.byteToClass,
    classes: artifact.classes,
    classSets: artifact.classSets,
    rules: rules,
    keywordRemaps: artifact.keywordRemaps
  )
}

struct LCRNG: Sendable {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func nextUInt64() -> UInt64 {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return state
  }

  mutating func nextInt(upperBound: Int) -> Int {
    precondition(upperBound > 0)
    return Int(nextUInt64() % UInt64(upperBound))
  }
}

private func buildFastWinners(
  bytes: [UInt8],
  validLen: Int,
  artifact: LexerArtifact
) -> [CandidateWinner] {
  var winners = (0..<bytes.count).map(CandidateWinner.noMatch(at:))

  let classSetsByID: [UInt16: Set<UInt8>] = Dictionary(
    uniqueKeysWithValues: artifact.classSets.map { decl in
      (decl.classSetID.rawValue, Set(decl.classes))
    })
  let byteToClass = artifact.byteToClass

  for position in 0..<validLen {
    var best = CandidateWinner.noMatch(at: position)

    for rule in artifact.rules where rule.family != .fallback {
      let len = fastMatchLength(
        rule: rule,
        bytes: bytes,
        start: position,
        validLen: validLen,
        byteToClass: byteToClass,
        classSetsByID: classSetsByID
      )
      guard len > 0 else { continue }

      let candidate = CandidateWinner(
        position: position,
        len: len,
        priorityRank: rule.priorityRank,
        ruleID: rule.ruleID,
        tokenKindID: rule.tokenKindID,
        mode: modeID(rule.mode)
      )
      if betterCandidateForTests(candidate, than: best) {
        best = candidate
      }
    }

    winners[position] = best
  }

  return winners
}

private func fastMatchLength(
  rule: LoweredRule,
  bytes: [UInt8],
  start: Int,
  validLen: Int,
  byteToClass: [UInt8],
  classSetsByID: [UInt16: Set<UInt8>]
) -> UInt16 {
  switch rule.plan {
  case .literal(let literal):
    let end = start + literal.count
    guard end <= validLen else { return 0 }
    if bytes[start..<end].elementsEqual(literal) {
      return UInt16(literal.count)
    }
    return 0

  case .runClassRun(let bodyClassSetID, let minLength):
    guard let bodySet = classSetsByID[bodyClassSetID] else { return 0 }
    var cursor = start
    let widthCap = Int(rule.maxWidth ?? UInt16.max)
    while cursor < validLen, cursor - start < widthCap {
      let classID = byteToClass[Int(bytes[cursor])]
      guard bodySet.contains(classID) else { break }
      cursor += 1
    }
    let len = cursor - start
    return len >= Int(minLength) ? UInt16(len) : 0

  case .runHeadTail(let headClassSetID, let tailClassSetID):
    guard
      let headSet = classSetsByID[headClassSetID],
      let tailSet = classSetsByID[tailClassSetID]
    else { return 0 }
    guard start < validLen else { return 0 }
    let firstClass = byteToClass[Int(bytes[start])]
    guard headSet.contains(firstClass) else { return 0 }
    var cursor = start + 1
    let widthCap = Int(rule.maxWidth ?? UInt16.max)
    while cursor < validLen, cursor - start < widthCap {
      let classID = byteToClass[Int(bytes[cursor])]
      guard tailSet.contains(classID) else { break }
      cursor += 1
    }
    let len = cursor - start
    return len >= Int(rule.minWidth) ? UInt16(len) : 0

  case .runPrefixed:
    return 0

  case .localWindow, .fallback:
    return 0
  }
}

private func betterCandidateForTests(_ lhs: CandidateWinner, than rhs: CandidateWinner) -> Bool {
  if lhs.len != rhs.len { return lhs.len > rhs.len }
  if lhs.len == 0 { return false }
  if lhs.priorityRank != rhs.priorityRank { return lhs.priorityRank < rhs.priorityRank }
  return lhs.ruleID < rhs.ruleID
}

private func modeID(_ mode: RuleMode) -> UInt8 {
  switch mode {
  case .emit:
    return 0
  case .skip:
    return 1
  }
}

private func buildCoverageMask(selected: [CandidateWinner], validLen: Int) -> [Bool] {
  guard validLen > 0 else { return [] }
  var covered = Array(repeating: false, count: validLen)
  for token in selected where token.len > 0 {
    let start = max(0, token.position)
    let end = min(validLen, token.position + Int(token.len))
    if start < end {
      for i in start..<end {
        covered[i] = true
      }
    }
  }
  return covered
}

private func buildErrorRuns(bytes: [UInt8], coverage: [Bool]) -> [TestErrorRun] {
  var runs: [TestErrorRun] = []
  var index = 0
  while index < coverage.count {
    if coverage[index] {
      index += 1
      continue
    }

    let start = index
    while index < coverage.count, !coverage[index] {
      index += 1
    }
    let runBytes = Array(bytes[start..<index])
    runs.append(
      TestErrorRun(
        start: start,
        end: index,
        lexeme: String(decoding: runBytes, as: UTF8.self)
      ))
  }
  return runs
}

private func remapTokenKind(
  winner: CandidateWinner,
  lexemeBytes: [UInt8],
  artifact: LexerArtifact
) -> UInt16 {
  for table in artifact.keywordRemaps where
    table.baseRuleID == winner.ruleID && table.baseTokenKindID == winner.tokenKindID
  {
    if lexemeBytes.count > Int(table.maxKeywordLength) {
      continue
    }
    if let hit = table.entries.first(where: { $0.lexeme == lexemeBytes }) {
      return hit.tokenKindID
    }
  }
  return winner.tokenKindID
}
