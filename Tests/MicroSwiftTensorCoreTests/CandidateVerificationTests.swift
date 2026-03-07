import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct CandidateVerificationTests {
  @Test
  func literalDifferentialMatchesBruteForceOnRandomInputs() {
    var rng = LCG(seed: 0xC0FFEE)

    for _ in 0..<250 {
      let length = rng.int(in: 1...24)
      let bytes = randomBytes(count: length, rng: &rng)
      let validLen = rng.int(in: 0...length)
      let validMask = makeValidMask(count: length, validLen: validLen)

      let literalLength = rng.int(in: 1...4)
      let literal = randomBytes(count: literalLength, rng: &rng)

      let actual = LiteralExecution.evaluateLiteral(
        bytes: bytes,
        validMask: validMask,
        literalBytes: literal
      )
      let expected = referenceLiteral(bytes: bytes, validMask: validMask, literal: literal)
      #expect(actual == expected)
    }
  }

  @Test(.enabled(if: requiresMLXEval))
  func literalCompiledPageDifferentialMatchesBruteForceOnRandomInputs() throws {
    let runtime = try makeLiteralCandidateRuntime()
    var rng = LCG(seed: 0xC0DE_C0DE)

    for _ in 0..<220 {
      let length = rng.int(in: 1...28)
      let bytes = randomBytes(count: length, rng: &rng)
      let validLen = rng.int(in: 0...length)
      let validMask = makeValidMask(count: length, validLen: validLen)
      let literalLength = rng.int(in: 1...4)
      let literal = randomBytes(count: literalLength, rng: &rng)

      let compiledPage = CompiledPageInput(
        bytes: bytes,
        validLen: Int32(validLen),
        baseOffset: 0,
        bucket: PageBucket(byteCapacity: Int32(length)),
        artifact: runtime
      )
      let actualTensor = LiteralExecution.evaluateLiteral(
        compiledPage: compiledPage,
        literalBytes: literal
      )
      let actual = actualTensor.asArray(UInt16.self)
      let expected = referenceLiteral(bytes: bytes, validMask: validMask, literal: literal)

      #expect(actual == expected)
    }
  }

  @Test
  func classRunDifferentialMatchesBruteForceOnRandomInputs() {
    var rng = LCG(seed: 0xA11CE)
    let runtime = makeClassRuntime()

    for _ in 0..<300 {
      let count = rng.int(in: 1...32)
      let classIDs = (0..<count).map { _ in UInt8(rng.int(in: 0...5)) }
      let validLen = rng.int(in: 0...count)
      let validMask = makeValidMask(count: count, validLen: validLen)
      let bodySetID = UInt16(rng.int(in: 0...2))
      let minLength = UInt16(rng.int(in: 1...5))

      let actual = ClassRunExecution.evaluateClassRun(
        classIDs: classIDs,
        validMask: validMask,
        bodyClassSetID: bodySetID,
        minLength: minLength,
        classSetRuntime: runtime
      )
      let expected = referenceClassRun(
        classIDs: classIDs,
        validMask: validMask,
        bodySetID: bodySetID,
        minLength: minLength,
        runtime: runtime
      )

      #expect(actual == expected)
    }
  }

  @Test
  func classRunDifferentialVariesClassSetTablesAndMinLength() {
    var rng = LCG(seed: 0x44CC11)

    for _ in 0..<220 {
      let runtime = randomClassRuntime(rng: &rng)
      let count = rng.int(in: 1...48)
      let maxClassID = max(0, runtime.numByteClasses - 1)
      let classIDs = (0..<count).map { _ in UInt8(rng.int(in: 0...maxClassID)) }
      let validLen = rng.int(in: 0...count)
      let validMask = makeValidMask(count: count, validLen: validLen)
      let bodySetID = UInt16(rng.int(in: 0...max(0, runtime.numClassSets - 1)))
      let minLength = UInt16(rng.int(in: 1...8))

      let actual = ClassRunExecution.evaluateClassRun(
        classIDs: classIDs,
        validMask: validMask,
        bodyClassSetID: bodySetID,
        minLength: minLength,
        classSetRuntime: runtime
      )
      let expected = referenceClassRun(
        classIDs: classIDs,
        validMask: validMask,
        bodySetID: bodySetID,
        minLength: minLength,
        runtime: runtime
      )

      #expect(actual == expected)
    }
  }

  @Test
  func headTailDifferentialMatchesBruteForceOnRandomInputs() {
    var rng = LCG(seed: 0xBEEF)
    let runtime = makeClassRuntime()

    for _ in 0..<300 {
      let count = rng.int(in: 1...32)
      let classIDs = (0..<count).map { _ in UInt8(rng.int(in: 0...5)) }
      let validLen = rng.int(in: 0...count)
      let validMask = makeValidMask(count: count, validLen: validLen)
      let headSetID = UInt16(rng.int(in: 0...2))
      let tailSetID = UInt16(rng.int(in: 0...2))

      let actual = HeadTailExecution.evaluateHeadTail(
        classIDs: classIDs,
        validMask: validMask,
        headClassSetID: headSetID,
        tailClassSetID: tailSetID,
        classSetRuntime: runtime
      )
      let expected = referenceHeadTail(
        classIDs: classIDs,
        validMask: validMask,
        headSetID: headSetID,
        tailSetID: tailSetID,
        runtime: runtime
      )

      #expect(actual == expected)
    }
  }

  @Test
  func headTailDifferentialVariesClassSetTables() {
    var rng = LCG(seed: 0x50EE77)

    for _ in 0..<220 {
      let runtime = randomClassRuntime(rng: &rng)
      let count = rng.int(in: 1...48)
      let maxClassID = max(0, runtime.numByteClasses - 1)
      let classIDs = (0..<count).map { _ in UInt8(rng.int(in: 0...maxClassID)) }
      let validLen = rng.int(in: 0...count)
      let validMask = makeValidMask(count: count, validLen: validLen)
      let headSetID = UInt16(rng.int(in: 0...max(0, runtime.numClassSets - 1)))
      let tailSetID = UInt16(rng.int(in: 0...max(0, runtime.numClassSets - 1)))

      let actual = HeadTailExecution.evaluateHeadTail(
        classIDs: classIDs,
        validMask: validMask,
        headClassSetID: headSetID,
        tailClassSetID: tailSetID,
        classSetRuntime: runtime
      )
      let expected = referenceHeadTail(
        classIDs: classIDs,
        validMask: validMask,
        headSetID: headSetID,
        tailSetID: tailSetID,
        runtime: runtime
      )

      #expect(actual == expected)
    }
  }

  @Test
  func prefixedDifferentialMatchesBruteForceOnRandomInputs() {
    var rng = LCG(seed: 0xFACE)
    let runtime = makePrefixedRuntime()
    let prefixes: [[UInt8]] = [
      Array("//".utf8),
      Array("/=".utf8),
      Array("--".utf8),
      Array("==".utf8),
    ]

    for _ in 0..<280 {
      let count = rng.int(in: 1...36)
      let bytes = randomPrefixedBytes(count: count, rng: &rng)
      let classIDs = classifyPrefixed(bytes)
      let validLen = rng.int(in: 0...count)
      let validMask = makeValidMask(count: count, validLen: validLen)
      let prefix = prefixes[rng.int(in: 0...(prefixes.count - 1))]
      let bodySetID: UInt16 = 0

      let includeStop = rng.bool()
      let stopSetID: UInt16? = includeStop ? 1 : nil
      let nextStop: [Int32]? = {
        guard includeStop else { return nil }
        let stopMask = zip(classIDs, validMask).map { classID, valid in
          valid && runtime.contains(setID: 1, classID: classID)
        }
        return NextStopHelper.computeNextStop(stopMask: stopMask, validLen: Int32(validLen))
      }()

      let actual = PrefixedExecution.evaluatePrefixed(
        bytes: bytes,
        classIDs: classIDs,
        validMask: validMask,
        prefix: prefix,
        bodyClassSetID: bodySetID,
        stopClassSetID: stopSetID,
        classSetRuntime: runtime,
        nextStop: nextStop
      )

      let expected = referencePrefixed(
        bytes: bytes,
        classIDs: classIDs,
        validMask: validMask,
        prefix: prefix,
        bodySetID: bodySetID,
        stopSetID: stopSetID,
        runtime: runtime,
        nextStop: nextStop
      )

      #expect(actual == expected)
    }
  }

  @Test
  func selectedRowsAreStrictlyIncreasingAndNonOverlapping() {
    var rng = LCG(seed: 0x1234_5678)

    for _ in 0..<180 {
      let count = rng.int(in: 1...30)
      let validLen = rng.int(in: 0...count)
      let validMask = makeValidMask(count: count, validLen: validLen)
      let winners = randomWinners(pageSize: count, rng: &rng)

      let (tokens, _) = modelSelect(winners: winners, validMask: validMask)
      let packedRows = tokens.map {
        PackedToken.pack(
          localStart: UInt16($0.start),
          length: UInt16($0.length),
          tokenKindID: $0.tokenKindID,
          flags: 0
        )
      }

      var lastStart = -1
      var lastEnd = 0
      for row in packedRows {
        let start = Int(PackedToken.unpackLocalStart(row))
        let length = Int(PackedToken.unpackLength(row))
        let end = start + length

        #expect(start > lastStart)
        #expect(start >= lastEnd)

        lastStart = start
        lastEnd = end
      }
    }
  }

  @Test
  func everyValidByteIsCoveredByTokenOrErrorRun() {
    var rng = LCG(seed: 0x4455_6677)

    for _ in 0..<180 {
      let count = rng.int(in: 1...36)
      let validLen = rng.int(in: 0...count)
      let validMask = makeValidMask(count: count, validLen: validLen)
      let winners = randomWinners(pageSize: count, rng: &rng)

      let (tokens, errors) = modelSelect(winners: winners, validMask: validMask)
      var covered = Array(repeating: false, count: count)

      for token in tokens {
        for i in token.start..<(token.start + token.length) {
          if i < count {
            covered[i] = true
          }
        }
      }

      for error in errors {
        for i in Int(error.start)..<Int(error.end) {
          if i < count {
            covered[i] = true
          }
        }
      }

      for i in 0..<count {
        if validMask[i] {
          #expect(covered[i])
        } else {
          #expect(!covered[i])
        }
      }
    }
  }

  @Test
  func keywordRemapDoesNotChangeSelectedTokenSpan() {
    var rng = LCG(seed: 0x0DDF00D)

    for _ in 0..<140 {
      let bytes = randomKeywordBytes(count: rng.int(in: 4...40), rng: &rng)
      let validMask = Array(repeating: true, count: bytes.count)
      let winners = randomWinners(pageSize: bytes.count, rng: &rng)
      let (tokens, _) = modelSelect(winners: winners, validMask: validMask)

      let remapped = applyKeywordRemap(
        tokens: tokens,
        bytes: bytes,
        table: ["if": 901, "let": 902, "for": 903]
      )

      #expect(remapped.count == tokens.count)
      for i in 0..<tokens.count {
        #expect(remapped[i].start == tokens[i].start)
        #expect(remapped[i].length == tokens[i].length)
      }
    }
  }

  @Test
  func overlapFixtureTripleEqualsWithDoubleAndSingle() {
    let selection = selectLiteralFixture(
      input: "===",
      rules: [
        .init(literal: "==", ruleID: 1, tokenKindID: 11, priorityRank: 0),
        .init(literal: "=", ruleID: 2, tokenKindID: 12, priorityRank: 1),
      ]
    )

    #expect(
      tokenTriples(selection.tokens) == [
        TokenTriple(start: 0, length: 2, tokenKindID: 11),
        TokenTriple(start: 2, length: 1, tokenKindID: 12),
      ])
    #expect(selection.errors.isEmpty)
  }

  @Test
  func overlapFixtureTripleEqualsArrow() {
    let selection = selectLiteralFixture(
      input: "===>",
      rules: [
        .init(literal: "==", ruleID: 1, tokenKindID: 21, priorityRank: 0),
        .init(literal: "=>", ruleID: 2, tokenKindID: 22, priorityRank: 0),
        .init(literal: "=", ruleID: 3, tokenKindID: 23, priorityRank: 1),
      ]
    )

    #expect(
      tokenTriples(selection.tokens) == [
        TokenTriple(start: 0, length: 2, tokenKindID: 21),
        TokenTriple(start: 2, length: 2, tokenKindID: 22),
      ])
    #expect(selection.errors.isEmpty)
  }

  @Test
  func overlapFixtureDashRunArrow() {
    let selection = selectLiteralFixture(
      input: "---->",
      rules: [
        .init(literal: "--", ruleID: 1, tokenKindID: 31, priorityRank: 0),
        .init(literal: "->", ruleID: 2, tokenKindID: 32, priorityRank: 0),
        .init(literal: "-", ruleID: 3, tokenKindID: 33, priorityRank: 1),
      ]
    )

    #expect(
      tokenTriples(selection.tokens) == [
        TokenTriple(start: 0, length: 2, tokenKindID: 31),
        TokenTriple(start: 2, length: 2, tokenKindID: 31),
      ])
    #expect(selection.errors == [ErrorSpan(start: 4, end: 5)])
  }

  @Test
  func overlapFixtureSlashDoubleEquals() {
    let selection = selectLiteralFixture(
      input: "/==",
      rules: [
        .init(literal: "/=", ruleID: 1, tokenKindID: 41, priorityRank: 0),
        .init(literal: "==", ruleID: 2, tokenKindID: 42, priorityRank: 0),
        .init(literal: "=", ruleID: 3, tokenKindID: 43, priorityRank: 1),
      ]
    )

    #expect(
      tokenTriples(selection.tokens) == [
        TokenTriple(start: 0, length: 2, tokenKindID: 41),
        TokenTriple(start: 2, length: 1, tokenKindID: 43),
      ])
    #expect(selection.errors.isEmpty)
  }

  @Test
  func overlapFixtureSlashFlood() {
    let selection = selectLiteralFixture(
      input: "////x",
      rules: [
        .init(literal: "///", ruleID: 1, tokenKindID: 51, priorityRank: 0),
        .init(literal: "//", ruleID: 2, tokenKindID: 52, priorityRank: 1),
        .init(literal: "/", ruleID: 3, tokenKindID: 53, priorityRank: 2),
        .init(literal: "x", ruleID: 4, tokenKindID: 54, priorityRank: 0),
      ]
    )

    #expect(
      tokenTriples(selection.tokens) == [
        TokenTriple(start: 0, length: 3, tokenKindID: 51),
        TokenTriple(start: 3, length: 1, tokenKindID: 53),
        TokenTriple(start: 4, length: 1, tokenKindID: 54),
      ])
    #expect(selection.errors.isEmpty)
  }

  @Test
  func longerLowPriorityCandidateInsideAcceptedTokenIsRejected() {
    let selection = selectLiteralFixture(
      input: "aaaaX",
      rules: [
        .init(literal: "aaaa", ruleID: 1, tokenKindID: 61, priorityRank: 0),
        .init(literal: "aaX", ruleID: 2, tokenKindID: 62, priorityRank: 9),
        .init(literal: "X", ruleID: 3, tokenKindID: 63, priorityRank: 0),
      ]
    )

    #expect(
      tokenTriples(selection.tokens) == [
        TokenTriple(start: 0, length: 4, tokenKindID: 61),
        TokenTriple(start: 4, length: 1, tokenKindID: 63),
      ])
    #expect(selection.errors.isEmpty)
  }

  @Test
  func laterValidTokenSurvivesAfterInternalRejectedCandidate() {
    let selection = selectLiteralFixture(
      input: "abcbcY",
      rules: [
        .init(literal: "abc", ruleID: 1, tokenKindID: 71, priorityRank: 0),
        .init(literal: "cbc", ruleID: 2, tokenKindID: 72, priorityRank: 0),
        .init(literal: "Y", ruleID: 3, tokenKindID: 73, priorityRank: 0),
      ]
    )

    #expect(
      tokenTriples(selection.tokens) == [
        TokenTriple(start: 0, length: 3, tokenKindID: 71),
        TokenTriple(start: 5, length: 1, tokenKindID: 73),
      ])
    #expect(selection.errors == [ErrorSpan(start: 3, end: 5)])
  }
}

private struct LiteralRuleSpec {
  let literal: String
  let ruleID: UInt16
  let tokenKindID: UInt16
  let priorityRank: UInt16
}

private struct ModelToken {
  let start: Int
  let length: Int
  let tokenKindID: UInt16
}

private struct TokenTriple: Equatable {
  let start: Int
  let length: Int
  let tokenKindID: UInt16
}

private struct LCG {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1
    return state
  }

  mutating func int(in range: ClosedRange<Int>) -> Int {
    let width = range.upperBound - range.lowerBound + 1
    return range.lowerBound + Int(next() % UInt64(width))
  }

  mutating func bool() -> Bool {
    (next() & 1) == 0
  }
}

private func randomBytes(count: Int, rng: inout LCG) -> [UInt8] {
  let alphabet = Array("abcxyz/=-_>\n01".utf8)
  return (0..<count).map { _ in alphabet[rng.int(in: 0...(alphabet.count - 1))] }
}

private func tokenTriples(_ tokens: [ModelToken]) -> [TokenTriple] {
  tokens.map { TokenTriple(start: $0.start, length: $0.length, tokenKindID: $0.tokenKindID) }
}

private func randomPrefixedBytes(count: Int, rng: inout LCG) -> [UInt8] {
  let alphabet = Array("/=-xabc\n ".utf8)
  return (0..<count).map { _ in alphabet[rng.int(in: 0...(alphabet.count - 1))] }
}

private func randomKeywordBytes(count: Int, rng: inout LCG) -> [UInt8] {
  let corpus = ["if", "let", "for", "foo", "bar", "x", "_"]
  var bytes: [UInt8] = []
  while bytes.count < count {
    if !bytes.isEmpty {
      bytes.append(UInt8(ascii: " "))
    }
    let word = corpus[rng.int(in: 0...(corpus.count - 1))]
    bytes.append(contentsOf: word.utf8)
  }
  return Array(bytes.prefix(count))
}

private func makeValidMask(count: Int, validLen: Int) -> [Bool] {
  (0..<count).map { $0 < validLen }
}

private func makeClassRuntime() -> ClassSetRuntime {
  let mask: [[Bool]] = [
    [false, true, true, false, false, false],
    [false, false, true, true, false, false],
    [true, false, false, false, false, false],
  ]
  return ClassSetRuntime(mask: mask, numClassSets: 3, numByteClasses: 6)
}

private func makePrefixedRuntime() -> ClassSetRuntime {
  let body = [true, true, true, true, true, false, true]
  let stop = [false, false, false, false, false, true, false]
  return ClassSetRuntime(mask: [body, stop], numClassSets: 2, numByteClasses: 7)
}

private func randomClassRuntime(rng: inout LCG) -> ClassSetRuntime {
  let numClassSets = rng.int(in: 1...4)
  let numByteClasses = rng.int(in: 1...8)
  var mask: [[Bool]] = []
  mask.reserveCapacity(numClassSets)

  for _ in 0..<numClassSets {
    var row = Array(repeating: false, count: numByteClasses)
    for classIndex in 0..<numByteClasses {
      row[classIndex] = rng.bool()
    }
    mask.append(row)
  }

  return ClassSetRuntime(
    mask: mask,
    numClassSets: numClassSets,
    numByteClasses: numByteClasses
  )
}

private func classifyPrefixed(_ bytes: [UInt8]) -> [UInt8] {
  bytes.map { byte in
    if byte == UInt8(ascii: "/") { return 0 }
    if byte == UInt8(ascii: "=") { return 1 }
    if byte == UInt8(ascii: ">") { return 2 }
    if byte == UInt8(ascii: "-") { return 3 }
    if byte == UInt8(ascii: "x") || byte == UInt8(ascii: "a") || byte == UInt8(ascii: "b")
      || byte == UInt8(ascii: "c")
    {
      return 4
    }
    if byte == UInt8(ascii: "\n") { return 5 }
    return 6
  }
}

private func referenceLiteral(bytes: [UInt8], validMask: [Bool], literal: [UInt8]) -> [UInt16] {
  let count = min(bytes.count, validMask.count)
  guard !literal.isEmpty, literal.count <= count else {
    return Array(repeating: 0, count: count)
  }

  var out = Array(repeating: UInt16(0), count: count)
  for start in 0...(count - literal.count) {
    var ok = true
    for i in 0..<literal.count {
      let pos = start + i
      if !validMask[pos] || bytes[pos] != literal[i] {
        ok = false
        break
      }
    }
    if ok {
      out[start] = UInt16(literal.count)
    }
  }
  return out
}

private func referenceClassRun(
  classIDs: [UInt8],
  validMask: [Bool],
  bodySetID: UInt16,
  minLength: UInt16,
  runtime: ClassSetRuntime
) -> [UInt16] {
  let count = min(classIDs.count, validMask.count)
  var out = Array(repeating: UInt16(0), count: count)
  var i = 0

  while i < count {
    let inBody = validMask[i] && runtime.contains(setID: bodySetID, classID: classIDs[i])
    if !inBody {
      i += 1
      continue
    }

    let start = i
    var end = i + 1
    while end < count && validMask[end]
      && runtime.contains(setID: bodySetID, classID: classIDs[end])
    {
      end += 1
    }

    let len = end - start
    if len >= Int(minLength) {
      out[start] = UInt16(len)
    }
    i = end
  }

  return out
}

private func referenceHeadTail(
  classIDs: [UInt8],
  validMask: [Bool],
  headSetID: UInt16,
  tailSetID: UInt16,
  runtime: ClassSetRuntime
) -> [UInt16] {
  let count = classIDs.count
  var out = Array(repeating: UInt16(0), count: count)

  for start in 0..<count {
    let valid = start < validMask.count && validMask[start]
    if !valid { continue }

    let classID = classIDs[start]
    let isHead = runtime.contains(setID: headSetID, classID: classID)
    let prevIsTail: Bool = {
      guard start > 0, start - 1 < validMask.count, validMask[start - 1] else { return false }
      return runtime.contains(setID: tailSetID, classID: classIDs[start - 1])
    }()

    if !isHead || prevIsTail { continue }

    var end = start
    while end + 1 < count {
      let next = end + 1
      if next >= validMask.count || !validMask[next] { break }
      if !runtime.contains(setID: tailSetID, classID: classIDs[next]) { break }
      end += 1
    }

    out[start] = UInt16(end - start + 1)
  }

  return out
}

private func referencePrefixed(
  bytes: [UInt8],
  classIDs: [UInt8],
  validMask: [Bool],
  prefix: [UInt8],
  bodySetID: UInt16,
  stopSetID: UInt16?,
  runtime: ClassSetRuntime,
  nextStop: [Int32]?
) -> [UInt16] {
  let count = min(bytes.count, classIDs.count, validMask.count)
  var out = Array(repeating: UInt16(0), count: count)

  for start in 0..<count {
    guard
      referencePrefixMatch(
        bytes: bytes, validMask: validMask, prefix: prefix, start: start, count: count)
    else {
      continue
    }

    let bodyStart = start + prefix.count
    var bodyEnd = bodyStart
    while bodyEnd < count && validMask[bodyEnd] {
      bodyEnd += 1
    }

    if let stopSetID {
      let stopIndex = referenceStopIndex(
        start: bodyStart,
        count: count,
        validMask: validMask,
        stopSetID: stopSetID,
        runtime: runtime,
        classIDs: classIDs,
        nextStop: nextStop
      )
      bodyEnd = min(bodyEnd, stopIndex)
    }

    var cursor = bodyStart
    while cursor < bodyEnd && runtime.contains(setID: bodySetID, classID: classIDs[cursor]) {
      cursor += 1
    }

    out[start] = UInt16(min(prefix.count + (cursor - bodyStart), Int(UInt16.max)))
  }

  return out
}

private func referencePrefixMatch(
  bytes: [UInt8],
  validMask: [Bool],
  prefix: [UInt8],
  start: Int,
  count: Int
) -> Bool {
  if prefix.isEmpty { return start < count && validMask[start] }
  if start + prefix.count > count { return false }

  for i in 0..<prefix.count {
    let pos = start + i
    if !validMask[pos] || bytes[pos] != prefix[i] {
      return false
    }
  }
  return true
}

private func referenceStopIndex(
  start: Int,
  count: Int,
  validMask: [Bool],
  stopSetID: UInt16,
  runtime: ClassSetRuntime,
  classIDs: [UInt8],
  nextStop: [Int32]?
) -> Int {
  guard start < count else { return start }

  if let nextStop, start < nextStop.count {
    let hit = Int(nextStop[start])
    if hit >= start && hit < count {
      return hit
    }
    if hit >= count {
      return count
    }
  }

  for i in start..<count {
    if !validMask[i] {
      return i
    }
    if runtime.contains(setID: stopSetID, classID: classIDs[i]) {
      return i
    }
  }

  return count
}

private func randomWinners(pageSize: Int, rng: inout LCG) -> [WinnerTuple] {
  (0..<pageSize).map { _ in
    let has = rng.bool()
    if !has {
      return .empty
    }

    return WinnerTuple(
      len: UInt16(rng.int(in: 1...6)),
      priorityRank: UInt16(rng.int(in: 0...8)),
      ruleID: UInt16(rng.int(in: 0...16)),
      tokenKindID: UInt16(rng.int(in: 1...120)),
      mode: 0
    )
  }
}

private func modelSelect(
  winners: [WinnerTuple],
  validMask: [Bool]
) -> (tokens: [ModelToken], errors: [ErrorSpan]) {
  let validLen = validMask.prefix { $0 }.count
  var tokens: [ModelToken] = []
  var errors: [ErrorSpan] = []

  var cursor = 0
  while cursor < validLen {
    if cursor < winners.count, winners[cursor].len > 0 {
      let length = max(1, min(Int(winners[cursor].len), validLen - cursor))
      tokens.append(
        ModelToken(start: cursor, length: length, tokenKindID: winners[cursor].tokenKindID)
      )
      cursor += length
      continue
    }

    let start = cursor
    cursor += 1
    while cursor < validLen {
      if cursor < winners.count, winners[cursor].len > 0 {
        break
      }
      cursor += 1
    }
    errors.append(ErrorSpan(start: Int32(start), end: Int32(cursor)))
  }

  return (tokens, errors)
}

private func applyKeywordRemap(
  tokens: [ModelToken],
  bytes: [UInt8],
  table: [String: UInt16]
) -> [ModelToken] {
  tokens.map { token in
    let end = min(token.start + token.length, bytes.count)
    let lexeme = String(decoding: bytes[token.start..<end], as: UTF8.self)
    if let mappedKind = table[lexeme] {
      return ModelToken(start: token.start, length: token.length, tokenKindID: mappedKind)
    }
    return token
  }
}

private func selectLiteralFixture(
  input: String,
  rules: [LiteralRuleSpec]
) -> (tokens: [ModelToken], errors: [ErrorSpan]) {
  let bytes = Array(input.utf8)
  let validMask = Array(repeating: true, count: bytes.count)
  let candidates = rules.map { spec in
    WinnerReduction.RuleCandidate(
      ruleID: spec.ruleID,
      tokenKindID: spec.tokenKindID,
      priorityRank: spec.priorityRank,
      mode: 0,
      candLen: LiteralExecution.evaluateLiteral(
        bytes: bytes,
        validMask: validMask,
        literalBytes: Array(spec.literal.utf8)
      )
    )
  }

  let winners = WinnerReduction.reduce(candidates: candidates, pageSize: bytes.count)
  return modelSelect(winners: winners, validMask: validMask)
}

private func makeLiteralCandidateRuntime() throws -> ArtifactRuntime {
  let declared = microSwiftV0.declare()
  let normalized = DeclaredSpec.normalize(declared)
  let validated = try NormalizedSpec.validate(normalized)
  let byteClasses = validated.buildByteClasses()
  let classSets = validated.buildClassSets(using: byteClasses)
  let classified = try validated.classifyRules(byteClasses: byteClasses, classSets: classSets)
  let artifact = try ArtifactSerializer.build(
    classified: classified,
    byteClasses: byteClasses,
    classSets: classSets,
    generatorVersion: "test"
  )
  return try ArtifactLoader.load(artifact)
}
