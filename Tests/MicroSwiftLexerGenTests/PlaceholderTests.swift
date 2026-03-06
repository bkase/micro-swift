import Testing

@testable import MicroSwiftLexerGen

@Suite("ByteSet Tests")
struct ByteSetTests {
  @Test func emptySet() {
    let s = ByteSet.empty
    #expect(s.isEmpty)
    #expect(s.count == 0)
    #expect(!s.contains(0))
    #expect(!s.contains(255))
  }

  @Test func allSet() {
    let s = ByteSet.all
    #expect(!s.isEmpty)
    #expect(s.count == 256)
    for b in UInt8.min...UInt8.max {
      #expect(s.contains(b))
    }
  }

  @Test func insertAndContains() {
    var s = ByteSet.empty
    s.insert(42)
    s.insert(200)
    #expect(s.contains(42))
    #expect(s.contains(200))
    #expect(!s.contains(41))
    #expect(s.count == 2)
  }

  @Test func rangeInit() {
    let digits = ByteSet(range: UInt8(ascii: "0")...UInt8(ascii: "9"))
    #expect(digits.count == 10)
    #expect(digits.contains(UInt8(ascii: "0")))
    #expect(digits.contains(UInt8(ascii: "9")))
    #expect(!digits.contains(UInt8(ascii: "a")))
  }

  @Test func complement() {
    let digits = ByteSet.asciiDigit
    let notDigits = digits.complement
    #expect(notDigits.count == 246)
    #expect(!notDigits.contains(UInt8(ascii: "0")))
    #expect(notDigits.contains(UInt8(ascii: "a")))
  }

  @Test func unionAndIntersection() {
    let a = ByteSet(bytes: [1, 2, 3])
    let b = ByteSet(bytes: [2, 3, 4])
    #expect(a.union(b).count == 4)
    #expect(a.intersection(b).count == 2)
  }

  @Test func members() {
    let s = ByteSet(bytes: [5, 3, 1])
    #expect(s.members == [1, 3, 5])
  }

  @Test func predefinedSets() {
    #expect(ByteSet.asciiDigit.count == 10)
    #expect(ByteSet.asciiLetter.count == 52)
    #expect(ByteSet.asciiIdentStart.count == 53)  // letters + underscore
    #expect(ByteSet.asciiIdentContinue.count == 63)  // letters + underscore + digits
    #expect(ByteSet.asciiWhitespace.contains(UInt8(ascii: " ")))
    #expect(ByteSet.asciiWhitespace.contains(UInt8(ascii: "\t")))
    #expect(ByteSet.asciiWhitespace.contains(UInt8(ascii: "\n")))
  }
}

@Suite("RawRegex DSL Tests")
struct RawRegexDSLTests {
  @Test func literalConstruction() {
    let r = literal("func")
    #expect(r == .literal([102, 117, 110, 99]))
  }

  @Test func concatenation() {
    let r = literal("//") <> zeroOrMore(not(.newline))
    if case .concat(let children) = r {
      #expect(children.count == 2)
    } else {
      Issue.record("Expected concat")
    }
  }

  @Test func repetitions() {
    let r1 = oneOrMore(.byteClass(.asciiDigit))
    if case .repetition(_, let min, let max) = r1 {
      #expect(min == 1)
      #expect(max == nil)
    } else {
      Issue.record("Expected repetition")
    }

    let r2 = optional(.byteClass(.asciiDigit))
    if case .repetition(_, let min, let max) = r2 {
      #expect(min == 0)
      #expect(max == 1)
    } else {
      Issue.record("Expected repetition")
    }
  }
}

@Suite("LexerSpec DSL Tests")
struct LexerSpecDSLTests {
  @Test func microSwiftV0HasCorrectName() {
    #expect(microSwiftV0.name == "MicroSwift.v0")
  }

  @Test func microSwiftV0RuleCount() {
    // 2 skip + 1 ident + 1 int + 13 punctuation/operators = 17 rules
    #expect(microSwiftV0.rules.count == 17)
  }

  @Test func microSwiftV0KeywordBlock() {
    #expect(microSwiftV0.keywordBlocks.count == 1)
    #expect(microSwiftV0.keywordBlocks[0].entries.count == 7)
    #expect(microSwiftV0.keywordBlocks[0].baseKindName == "ident")
  }

  @Test func skipRulesHaveCorrectMode() {
    let skips = microSwiftV0.rules.filter { $0.mode == .skip }
    #expect(skips.count == 2)
    #expect(skips[0].kindName == "ws")
    #expect(skips[1].kindName == "lineComment")
  }

  @Test func identRuleHasIdentifierRole() {
    let identRule = microSwiftV0.rules.first { $0.role == .identifier }
    #expect(identRule != nil)
    #expect(identRule?.kindName == "ident")
  }
}

@Suite("Declaration Lowering Tests")
struct DeclarationLoweringTests {
  @Test func declarePreservesName() {
    let declared = microSwiftV0.declare()
    #expect(declared.name == "MicroSwift.v0")
  }

  @Test func declarePreservesRuleCount() {
    let declared = microSwiftV0.declare()
    #expect(declared.rules.count == 17)
  }

  @Test func declarePreservesKeywordBlocks() {
    let declared = microSwiftV0.declare()
    #expect(declared.keywordBlocks.count == 1)
    #expect(declared.keywordBlocks[0].baseKindName == "ident")
    #expect(declared.keywordBlocks[0].entries.count == 7)
  }

  @Test func keywordEntriesHaveCorrectBytes() {
    let declared = microSwiftV0.declare()
    let funcEntry = declared.keywordBlocks[0].entries.first { $0.lexeme == "func" }
    #expect(funcEntry != nil)
    #expect(funcEntry?.lexemeBytes == [102, 117, 110, 99])
  }

  @Test func declaredRulesHaveSourceSpans() {
    let declared = microSwiftV0.declare()
    for rule in declared.rules {
      #expect(!rule.sourceSpan.fileID.isEmpty)
      #expect(rule.sourceSpan.line > 0)
    }
  }

  @Test func ruleModesPreserved() {
    let declared = microSwiftV0.declare()
    let skipRules = declared.rules.filter { $0.mode == .skip }
    let emitRules = declared.rules.filter { $0.mode == .emit }
    #expect(skipRules.count == 2)
    #expect(emitRules.count == 15)
  }

  @Test func ruleRolesPreserved() {
    let declared = microSwiftV0.declare()
    let identRules = declared.rules.filter { $0.role == .identifier }
    #expect(identRules.count == 1)
    #expect(identRules[0].declaredKindName == "ident")
  }

  @Test func declarationOrderMatchesSourceOrder() {
    let declared = microSwiftV0.declare()
    let names = declared.rules.map(\.declaredKindName)
    #expect(names[0] == "ws")
    #expect(names[1] == "lineComment")
    #expect(names[2] == "ident")
    #expect(names[3] == "int")
    #expect(names[4] == "arrow")
  }
}

@Suite("Normalization Tests")
struct NormalizationTests {
  @Test func normalizesMicroSwiftSpecWithStableIDs() {
    let declared = microSwiftV0.declare()
    let normalized = DeclaredSpec.normalize(declared)

    #expect(normalized.name == "MicroSwift.v0")
    #expect(normalized.rules.count == 17)
    #expect(normalized.rules[0].ruleID == RuleID(0))
    #expect(normalized.rules[0].tokenKindID == TokenKindID(0))
    #expect(normalized.rules[1].tokenKindID == TokenKindID(1))
    #expect(normalized.rules[2].name == "ident")
    #expect(normalized.rules[2].tokenKindID == TokenKindID(2))

    let keywordBlock = normalized.keywordBlocks[0]
    #expect(keywordBlock.baseKindName == "ident")
    #expect(keywordBlock.baseTokenKindID == TokenKindID(2))
    #expect(keywordBlock.entries.count == 7)
  }

  @Test func normalizationFlattensConcatAndMergesLiterals() {
    let raw = literal("a") <> (literal("b") <> literal("c"))
    let normalized = NormalizedRegex.normalize(raw)
    #expect(normalized == .literal([97, 98, 99]))
  }

  @Test func normalizationSortsAndDedupesAlternation() {
    let raw = alt(literal("b"), literal("a"), literal("b"))
    let normalized = NormalizedRegex.normalize(raw)
    #expect(normalized == .alt([.literal([97]), .literal([98])]))
  }

  @Test func normalizationIsIdempotentByCanonicalKey() {
    let once = NormalizedRegex.normalize(literal("a") <> oneOrMore(.byteClass(.asciiDigit)))
    let twice = NormalizedRegex.normalize(raw(from: once))
    #expect(once == twice)
    #expect(once.canonicalKey == twice.canonicalKey)
  }

  @Test func computesRegexPropsForConcatAndAlt() {
    let concatRegex = NormalizedRegex.normalize(literal("ab") <> optional(literal("c")))
    let concatProps = concatRegex.props
    #expect(!concatProps.nullable)
    #expect(concatProps.minWidth == 2)
    #expect(concatProps.maxWidth == 3)
    #expect(concatProps.firstByteSet.contains(UInt8(ascii: "a")))

    let altRegex = NormalizedRegex.normalize(alt(optional(literal("x")), literal("yz")))
    let altProps = altRegex.props
    #expect(altProps.nullable)
    #expect(altProps.minWidth == 0)
    #expect(altProps.maxWidth == 2)
    #expect(altProps.firstByteSet.contains(UInt8(ascii: "x")))
    #expect(altProps.firstByteSet.contains(UInt8(ascii: "y")))
  }

  private func raw(from normalized: NormalizedRegex) -> RawRegex {
    switch normalized {
    case .never:
      return .byteClass(.empty)
    case .epsilon:
      return .literal([])
    case .literal(let bytes):
      return .literal(bytes)
    case .byteClass(let set):
      return .byteClass(set)
    case .concat(let children):
      return .concat(children.map(raw(from:)))
    case .alt(let children):
      return .alt(children.map(raw(from:)))
    case .repetition(let child, let min, let max):
      return .repetition(raw(from: child), min: min, max: max)
    }
  }
}
