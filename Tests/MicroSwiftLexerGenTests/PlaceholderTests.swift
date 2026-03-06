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

@Suite("Validation Tests")
struct ValidationTests {
  @Test func validatesMicroSwiftSpec() throws {
    let normalized = DeclaredSpec.normalize(microSwiftV0.declare())
    let validated = try NormalizedSpec.validate(normalized)
    #expect(validated.rules.count == 17)
  }

  @Test func rejectsNullableRule() {
    let spec = LexerSpec(name: "nullable") {
      token("maybe", optional(literal("a")))
    }
    let normalized = DeclaredSpec.normalize(spec.declare())

    do {
      _ = try NormalizedSpec.validate(normalized)
      Issue.record("Expected validation to fail")
    } catch let error as ValidationError {
      #expect(error.diagnostics.contains { $0.code == .nullableRule })
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func rejectsDuplicateTopLevelTokenKind() {
    let spec = LexerSpec(name: "duplicateKind") {
      token("dup", literal("a"))
      token("dup", literal("b"))
    }
    let normalized = DeclaredSpec.normalize(spec.declare())

    do {
      _ = try NormalizedSpec.validate(normalized)
      Issue.record("Expected validation to fail")
    } catch let error as ValidationError {
      #expect(error.diagnostics.contains { $0.code == .duplicateTopLevelTokenKind })
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func rejectsDuplicateKeywordLexemeAndKind() {
    let spec = LexerSpec(name: "duplicateKeyword") {
      let ident = identifier(
        "ident",
        .byteClass(.asciiIdentStart) <> zeroOrMore(.byteClass(.asciiIdentContinue))
      )
      keywords(for: ident) {
        keyword("if", as: "kwIf")
        keyword("if", as: "kwIf2")
        keyword("else", as: "kwIf")
      }
    }
    let normalized = DeclaredSpec.normalize(spec.declare())

    do {
      _ = try NormalizedSpec.validate(normalized)
      Issue.record("Expected validation to fail")
    } catch let error as ValidationError {
      #expect(error.diagnostics.contains { $0.code == .duplicateKeywordLexeme })
      #expect(error.diagnostics.contains { $0.code == .duplicateKeywordKind })
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func rejectsKeywordNotMatchedByBaseRule() {
    let spec = LexerSpec(name: "badKeyword") {
      let ident = identifier(
        "ident",
        .byteClass(.asciiIdentStart) <> zeroOrMore(.byteClass(.asciiIdentContinue))
      )
      keywords(for: ident) {
        keyword("123", as: "kwNumeric")
      }
    }
    let normalized = DeclaredSpec.normalize(spec.declare())

    do {
      _ = try NormalizedSpec.validate(normalized)
      Issue.record("Expected validation to fail")
    } catch let error as ValidationError {
      #expect(error.diagnostics.contains { $0.code == .keywordNotMatchedByBaseRule })
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}

@Suite("Byte Class Tests")
struct ByteClassTests {
  @Test func buildsDeterministicByteClassesForMicroSwift() throws {
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(microSwiftV0.declare()))
    let classesA = validated.buildByteClasses()
    let classesB = validated.buildByteClasses()
    #expect(classesA == classesB)
    #expect(classesA.byteToClass.count == 256)
    #expect(!classesA.classes.isEmpty)
  }

  @Test func classesPartitionAllBytesExactlyOnce() throws {
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(microSwiftV0.declare()))
    let byteClasses = validated.buildByteClasses()

    let allMembers = byteClasses.classes.flatMap(\.bytes)
    #expect(allMembers.count == 256)
    #expect(Set(allMembers).count == 256)
    #expect(Set(allMembers) == Set(UInt8.min...UInt8.max))
  }

  @Test func bytesInSameClassSharePrimitiveMembership() throws {
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(microSwiftV0.declare()))
    let byteClasses = validated.buildByteClasses()
    let predicates = primitivePredicates(from: validated)

    for byteClass in byteClasses.classes {
      guard let first = byteClass.bytes.first else { continue }
      let baseline = predicates.map { $0.contains(first) }
      for byte in byteClass.bytes.dropFirst() {
        let membership = predicates.map { $0.contains(byte) }
        #expect(membership == baseline)
      }
    }
  }

  private func primitivePredicates(from spec: ValidatedSpec) -> [ByteSet] {
    var predicates: [ByteSet] = []
    for rule in spec.rules {
      predicates.append(rule.props.firstByteSet)
      predicates.append(contentsOf: primitiveSets(in: rule.regex))
    }
    return Array(Set(predicates))
  }

  private func primitiveSets(in regex: NormalizedRegex) -> [ByteSet] {
    switch regex {
    case .never, .epsilon:
      return []
    case .literal(let bytes):
      return bytes.map { ByteSet(bytes: [$0]) }
    case .byteClass(let set):
      return [set]
    case .concat(let children), .alt(let children):
      return children.flatMap(primitiveSets(in:))
    case .repetition(let child, _, _):
      return primitiveSets(in: child)
    }
  }
}

@Suite("Class Set Tests")
struct ClassSetTests {
  @Test func buildsDeterministicClassSets() throws {
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(microSwiftV0.declare()))
    let byteClasses = validated.buildByteClasses()
    let a = validated.buildClassSets(using: byteClasses)
    let b = validated.buildClassSets(using: byteClasses)
    #expect(a == b)
    #expect(!a.classSets.isEmpty)
  }

  @Test func classSetsUseLexicographicStableOrdering() throws {
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(microSwiftV0.declare()))
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let members = classSets.classSets.map(\.classes)
    #expect(members == members.sorted { $0.lexicographicallyPrecedes($1) })
  }

  @Test func projectedMembershipInvariantHolds() throws {
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(microSwiftV0.declare()))
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)

    for byteSet in validated.relevantByteSetsForLowering() {
      let classSetID = try #require(classSets.classSetID(for: byteSet, in: byteClasses))
      let projected = try #require(
        classSets.classSets.first { $0.classSetID == classSetID }?.classes)
      let projectedSet = Set(projected)

      for byte in UInt8.min...UInt8.max {
        let inOriginal = byteSet.contains(byte)
        let classID = byteClasses.byteToClass[Int(byte)]
        let inProjected = projectedSet.contains(classID)
        #expect(inOriginal == inProjected)
      }
    }
  }
}

@Suite("Family Classifier Tests")
struct FamilyClassifierTests {
  @Test func classifiesMicroSwiftRulesIntoLiteralAndRun() throws {
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(microSwiftV0.declare()))
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let classified = try validated.classifyRules(
      byteClasses: byteClasses,
      classSets: classSets,
      options: .init(maxLocalWindowBytes: 8, enableFallback: true, maxFallbackStatesPerRule: 256)
    )

    let byName = Dictionary(
      uniqueKeysWithValues: classified.rules.map { ($0.rule.name, $0.plan.family) })

    #expect(byName["ws"] == .run)
    #expect(byName["lineComment"] == .run)
    #expect(byName["ident"] == .run)
    #expect(byName["int"] == .run)
    #expect(byName["eqEq"] == .literal)
    #expect(byName["arrow"] == .literal)
    #expect(byName["comma"] == .literal)
  }

  @Test func fallsBackWhenFallbackEnabledAndNoCheaperFamilyMatches() throws {
    let spec = LexerSpec(name: "window-or-fallback") {
      token("alt", alt(literal("ab"), literal("cd")))
    }
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(spec.declare()))
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let classified = try validated.classifyRules(
      byteClasses: byteClasses,
      classSets: classSets,
      options: .init(maxLocalWindowBytes: 1, enableFallback: true, maxFallbackStatesPerRule: 256)
    )

    #expect(classified.rules.count == 1)
    #expect(classified.rules[0].plan.family == .fallback)
    guard case .fallback(let plan) = classified.rules[0].plan else {
      Issue.record("Expected fallback plan")
      return
    }
    #expect(plan.startState == 1)
    #expect(plan.transitionRowStride == plan.classCount)
    #expect(plan.transitions.count == Int(plan.stateCount * UInt32(plan.transitionRowStride)))
    #expect(plan.transitions.prefix(Int(plan.classCount)).allSatisfy { $0 == 0 })  // dead-state row
    #expect(plan.transitions.allSatisfy { $0 < plan.stateCount })
  }

  @Test func errorsWhenFallbackDisabledAndRuleNeedsFallback() throws {
    let spec = LexerSpec(name: "fallback-disabled") {
      token("alt", alt(literal("ab"), literal("cd")))
    }
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(spec.declare()))
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)

    do {
      _ = try validated.classifyRules(
        byteClasses: byteClasses,
        classSets: classSets,
        options: .init(maxLocalWindowBytes: 1, enableFallback: false, maxFallbackStatesPerRule: 256)
      )
      Issue.record("Expected classification failure")
    } catch let error as ClassificationError {
      #expect(error.message.contains("fallback is disabled"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func fallbackPlanIsDeterministicAcrossRuns() throws {
    let spec = LexerSpec(name: "fallback-deterministic") {
      token("alt", alt(literal("ab"), literal("cd")))
    }
    let validated = try NormalizedSpec.validate(DeclaredSpec.normalize(spec.declare()))
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let opts = CompileOptions(
      maxLocalWindowBytes: 1, enableFallback: true, maxFallbackStatesPerRule: 256)

    let a = try validated.classifyRules(
      byteClasses: byteClasses, classSets: classSets, options: opts)
    let b = try validated.classifyRules(
      byteClasses: byteClasses, classSets: classSets, options: opts)
    #expect(a == b)
  }
}

@Suite("Artifact Serializer Tests")
struct ArtifactSerializerTests {
  @Test func artifactRoundTrips() throws {
    let artifact = try buildMicroSwiftArtifact()
    let encoded = try ArtifactSerializer.encode(artifact)
    let decoded = try ArtifactSerializer.decode(encoded)
    #expect(decoded == artifact)
  }

  @Test func artifactEncodingIsDeterministic() throws {
    let artifactA = try buildMicroSwiftArtifact()
    let artifactB = try buildMicroSwiftArtifact()
    let bytesA = try ArtifactSerializer.encode(artifactA)
    let bytesB = try ArtifactSerializer.encode(artifactB)
    #expect(bytesA == bytesB)
  }

  @Test func specHashTracksRuleSemantics() throws {
    let specA = LexerSpec(name: "hash-semantics") {
      token("t", literal("ab"))
    }
    let specB = LexerSpec(name: "hash-semantics") {
      token("t", literal("ac"))
    }

    let artifactA = try buildArtifact(
      from: specA,
      options: .init(maxLocalWindowBytes: 8, enableFallback: true, maxFallbackStatesPerRule: 256)
    )
    let artifactB = try buildArtifact(
      from: specB,
      options: .init(maxLocalWindowBytes: 8, enableFallback: true, maxFallbackStatesPerRule: 256)
    )

    #expect(artifactA.specHashHex != artifactB.specHashHex)
  }

  @Test func fallbackLayoutIsDenseRowMajor() throws {
    let spec = LexerSpec(name: "fallback-artifact") {
      token("alt", alt(literal("ab"), literal("cd")))
    }
    let artifact = try buildArtifact(
      from: spec,
      options: .init(maxLocalWindowBytes: 1, enableFallback: true, maxFallbackStatesPerRule: 256)
    )
    let fallbackRule = try #require(artifact.rules.first(where: { $0.family == .fallback }))

    if case .fallback(let stateCount, let classCount, let rowStride, _, _, let transitions) =
      fallbackRule.plan
    {
      #expect(rowStride == classCount)
      #expect(transitions.count == Int(stateCount * UInt32(rowStride)))
      #expect(transitions.allSatisfy { $0 < stateCount })
    } else {
      Issue.record("Expected fallback rule plan")
    }
  }

  @Test func rejectsFiniteRuleWidthBeyondUInt16Range() {
    let spec = LexerSpec(name: "too-wide") {
      token("wide", repeated(.byteClass(.asciiIdentContinue), atLeast: 70_000))
    }

    do {
      _ = try buildArtifact(
        from: spec,
        options: .init(maxLocalWindowBytes: 8, enableFallback: true, maxFallbackStatesPerRule: 256)
      )
      Issue.record("Expected artifact build failure")
    } catch let error as ValidationError {
      #expect(error.diagnostics.contains { $0.code == .finiteRuleWidthOutOfRange })
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func buildMicroSwiftArtifact() throws -> LexerArtifact {
    try buildArtifact(
      from: microSwiftV0,
      options: .init(maxLocalWindowBytes: 8, enableFallback: true, maxFallbackStatesPerRule: 256)
    )
  }

  private func buildArtifact(from spec: LexerSpec, options: CompileOptions) throws -> LexerArtifact
  {
    let validated = try NormalizedSpec.validate(
      DeclaredSpec.normalize(spec.declare()), options: options)
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let classified = try validated.classifyRules(
      byteClasses: byteClasses,
      classSets: classSets,
      options: options
    )
    return try ArtifactSerializer.build(
      classified: classified,
      byteClasses: byteClasses,
      classSets: classSets,
      generatorVersion: "test"
    )
  }
}
