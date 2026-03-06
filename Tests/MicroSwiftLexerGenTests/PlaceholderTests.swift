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
