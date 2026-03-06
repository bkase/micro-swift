import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite struct CapabilityValidatorTests {
  @Test func v1FallbackAcceptsLiteralRunAndFallback() {
    let artifact = makeArtifact(
      rules: [
        makeLiteralRule(ruleID: 1, name: "literal"),
        makeRunRule(ruleID: 2, name: "run"),
        makeFallbackRule(ruleID: 3, name: "fallback"),
      ],
      maxLookahead: 8
    )

    let diagnostics = CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback)
    #expect(diagnostics.isEmpty)
  }

  @Test func v1FallbackRejectsLocalWindow() {
    let artifact = makeArtifact(
      rules: [
        LoweredRule(
          ruleID: 10,
          name: "window",
          tokenKindID: 1,
          mode: .emit,
          family: .localWindow,
          priorityRank: 0,
          minWidth: 1,
          maxWidth: 2,
          firstClassSetID: 0,
          plan: .localWindow(maxWidth: 2)
        )
      ]
    )

    let diagnostics = CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback)
    #expect(diagnostics.count == 1)
    #expect(diagnostics[0].reason == .localWindowPresent)
  }

  @Test func v1FallbackRejectsInvalidFallbackPayload() {
    let invalid = LoweredRule(
      ruleID: 20,
      name: "badFallback",
      tokenKindID: 1,
      mode: .emit,
      family: .fallback,
      priorityRank: 0,
      minWidth: 1,
      maxWidth: 4,
      firstClassSetID: 0,
      plan: .fallback(
        stateCount: 2,
        classCount: 1,
        transitionRowStride: 1,
        startState: 0,
        acceptingStates: [1],
        transitions: [0]  // should be 2 entries
      )
    )
    let artifact = makeArtifact(rules: [invalid])

    let diagnostics = CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback)
    #expect(diagnostics.contains { $0.reason == .missingTable })
  }

  @Test func v1FallbackRejectsStateCapExceeding128() {
    let artifact = makeArtifact(
      rules: [
        makeFallbackRule(ruleID: 30, name: "a", stateCount: 80, maxWidth: 4),
        makeFallbackRule(ruleID: 31, name: "b", stateCount: 60, maxWidth: 4),
      ],
      maxLookahead: 8
    )

    let diagnostics = CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback)
    #expect(diagnostics.contains { $0.ruleID == 31 && $0.reason == .stateCapExceeded })
  }

  @Test func v1FallbackRejectsClassCapExceeding128() {
    let artifact = makeArtifact(
      rules: [
        makeFallbackRule(ruleID: 32, name: "tooManyClasses", classCount: 129, maxWidth: 4)
      ],
      maxLookahead: 8
    )

    let diagnostics = CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback)
    #expect(diagnostics.contains { $0.ruleID == 32 && $0.reason == .classCapExceeded })
  }

  @Test func v1FallbackRejectsUnboundedFallbackWidth() {
    let unbounded = makeFallbackRule(ruleID: 40, name: "wide", maxWidth: nil)
    let artifact = makeArtifact(rules: [unbounded], maxLookahead: 8)

    let diagnostics = CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback)
    #expect(diagnostics.contains { $0.reason == .widthExceeded })
  }

  @Test func v1FallbackRejectsLookaheadMismatch() {
    let artifact = makeArtifact(
      rules: [makeFallbackRule(ruleID: 50, name: "tooWide", maxWidth: 12)],
      maxLookahead: 8
    )

    let diagnostics = CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback)
    #expect(diagnostics.contains { $0.reason == .maxLookaheadMismatch })
  }

  @Test func v1FallbackRejectsMissingRuleMetadata() {
    let rule = makeFallbackRule(ruleID: 60, name: "", tokenKindID: 999, maxWidth: 4)
    let artifact = makeArtifact(rules: [rule], tokenKindIDs: [1], maxLookahead: 8)

    let diagnostics = CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback)
    #expect(diagnostics.contains { $0.reason == .missingTable })
  }

  @Test func diagnosticDescriptionIsStructured() {
    let diagnostic = CapabilityDiagnostic(
      ruleID: 7,
      ruleName: "foo",
      family: .fallback,
      reason: .missingTable
    )
    #expect(
      diagnostic.description
        == "artifact-capability-error: unsupported fallback ruleID=7 name=foo reason=missing-table"
    )
  }
}

private func makeArtifact(
  rules: [LoweredRule],
  tokenKindIDs: [UInt16] = [1],
  maxLookahead: UInt16 = 8
) -> LexerArtifact {
  LexerArtifact(
    formatVersion: 1,
    specName: "Fixture",
    specHashHex: "deadbeef",
    generatorVersion: "tests",
    runtimeHints: RuntimeHints(
      maxLiteralLength: 8,
      maxBoundedRuleWidth: maxLookahead,
      maxDeterministicLookaheadBytes: maxLookahead
    ),
    tokenKinds: tokenKindIDs.map {
      TokenKindDecl(tokenKindID: $0, name: "k\($0)", defaultMode: .emit)
    },
    byteToClass: Array(repeating: 0, count: 256),
    classes: [ByteClassDecl(classID: 0, bytes: [0])],
    classSets: [ClassSetDecl(classSetID: ClassSetID(0), classes: [0])],
    rules: rules,
    keywordRemaps: []
  )
}

private func makeLiteralRule(ruleID: UInt16, name: String) -> LoweredRule {
  LoweredRule(
    ruleID: ruleID,
    name: name,
    tokenKindID: 1,
    mode: .emit,
    family: .literal,
    priorityRank: ruleID,
    minWidth: 1,
    maxWidth: 1,
    firstClassSetID: 0,
    plan: .literal(bytes: [0x61])
  )
}

private func makeRunRule(ruleID: UInt16, name: String) -> LoweredRule {
  LoweredRule(
    ruleID: ruleID,
    name: name,
    tokenKindID: 1,
    mode: .emit,
    family: .run,
    priorityRank: ruleID,
    minWidth: 1,
    maxWidth: 8,
    firstClassSetID: 0,
    plan: .runClassRun(bodyClassSetID: 0, minLength: 1)
  )
}

private func makeFallbackRule(
  ruleID: UInt16,
  name: String,
  tokenKindID: UInt16 = 1,
  stateCount: UInt32 = 2,
  classCount: UInt16 = 1,
  maxWidth: UInt16? = 4
) -> LoweredRule {
  LoweredRule(
    ruleID: ruleID,
    name: name,
    tokenKindID: tokenKindID,
    mode: .emit,
    family: .fallback,
    priorityRank: ruleID,
    minWidth: 1,
    maxWidth: maxWidth,
    firstClassSetID: 0,
    plan: .fallback(
      stateCount: stateCount,
      classCount: classCount,
      transitionRowStride: classCount,
      startState: 0,
      acceptingStates: [1],
      transitions: Array(repeating: 0, count: Int(stateCount) * Int(classCount))
    )
  )
}
