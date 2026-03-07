import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct CompiledPageInputTests {
  @Test
  func compiledPageInputIsBucketStableAndDeterministic() throws {
    let runtime = try makeMicroSwiftRuntime()
    let bucket = PageBucket(byteCapacity: 4096)
    let bytes = Array("let x = 1".utf8)

    let first = CompiledPageInput(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 12,
      bucket: bucket,
      artifact: runtime
    )
    let second = CompiledPageInput(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 12,
      bucket: bucket,
      artifact: runtime
    )

    #expect(first.byteTensorShape == [4096])
    #expect(first.byteTensorDType == .uint8)
    #expect(first.classIDTensorShape == [4096])
    #expect(first.classIDTensorDType == .uint16)
    #expect(first.validMaskTensorShape == [4096])
    #expect(first.validMaskTensorDType == .bool)

    let firstBytes = first.hostPaddedBytesForInspection()
    let secondBytes = second.hostPaddedBytesForInspection()
    #expect(firstBytes.count == 4096)
    #expect(firstBytes == secondBytes)
    #expect(firstBytes[bytes.count] == PageBucket.neutralPaddingByte)
    #expect(firstBytes[4095] == PageBucket.neutralPaddingByte)
  }

  @Test
  func deviceClassIDsMatchScalarOracleForRandomizedInput() throws {
    let runtime = try makeMicroSwiftRuntime()
    let bucket = PageBucket(byteCapacity: 4096)
    var rng = CompiledPageLCRNG(seed: 0xA11CE)

    for _ in 0..<16 {
      let validLen = rng.nextInt(upperBound: 512)
      let payload = (0..<validLen).map { _ in UInt8(truncatingIfNeeded: rng.nextWord()) }
      let page = CompiledPageInput(
        bytes: payload,
        validLen: Int32(validLen),
        baseOffset: 0,
        bucket: bucket,
        artifact: runtime
      )

      let hostView = page.extractHostExecutionView(at: HostExtractionBoundary.testInspection)
      let expected = ByteClassifier.classify(
        bytes: hostView.bytes,
        byteToClassLUT: runtime.hostByteToClassLUT()
      )

      #expect(hostView.classIDs == expected)
    }
  }

  @Test
  func paddedTailCannotCreateLiteralMatchBeyondValidLen() throws {
    let runtime = try makeLiteralRuntime()
    let bucket = PageBucket(byteCapacity: 4096)

    let page = CompiledPageInput(
      bytes: Array("a".utf8),
      validLen: 1,
      baseOffset: 0,
      bucket: bucket,
      artifact: runtime
    )

    let result = TensorLexer.lexPage(
      compiledPage: page,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v0)
    )

    #expect(result.rowCount == 0)
    #expect(result.hostPackedRows().allSatisfy { $0 == 0 })
  }

  @Test
  func hostExtractionBoundaryIsExplicit() throws {
    let runtime = try makeMicroSwiftRuntime()
    let bucket = PageBucket(byteCapacity: 4096)
    let page = CompiledPageInput(
      bytes: Array("abc".utf8),
      validLen: 3,
      baseOffset: 0,
      bucket: bucket,
      artifact: runtime
    )

    let finalView = page.extractHostExecutionView(at: HostExtractionBoundary.finalPackedRows)
    let testView = page.extractHostExecutionView(at: HostExtractionBoundary.testInspection)

    #expect(finalView.bytes == testView.bytes)
    #expect(finalView.classIDs == testView.classIDs)
    #expect(finalView.validMask == testView.validMask)
    #expect(finalView.validMask.prefix(3).allSatisfy { $0 })
    #expect(finalView.validMask[3] == false)
  }
}

private struct CompiledPageLCRNG {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func nextWord() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1
    return state
  }

  mutating func nextInt(upperBound: Int) -> Int {
    precondition(upperBound > 0)
    return Int(nextWord() % UInt64(upperBound))
  }
}

private func makeMicroSwiftRuntime() throws -> ArtifactRuntime {
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

private func makeLiteralRuntime() throws -> ArtifactRuntime {
  var byteToClass = Array(repeating: UInt8(0), count: 256)
  byteToClass[Int(Character("a").asciiValue!)] = 1
  byteToClass[Int(Character("b").asciiValue!)] = 2

  let artifact = LexerArtifact(
    formatVersion: 1,
    specName: "compiled-page-literal",
    specHashHex: String(repeating: "0", count: 64),
    generatorVersion: "tests",
    runtimeHints: RuntimeHints(
      maxLiteralLength: 2,
      maxBoundedRuleWidth: 2,
      maxDeterministicLookaheadBytes: 2
    ),
    tokenKinds: [TokenKindDecl(tokenKindID: 1, name: "ab", defaultMode: .emit)],
    byteToClass: byteToClass,
    classes: [
      ByteClassDecl(classID: 1, bytes: [Character("a").asciiValue!]),
      ByteClassDecl(classID: 2, bytes: [Character("b").asciiValue!]),
    ],
    classSets: [],
    rules: [
      LoweredRule(
        ruleID: 11,
        name: "ab-literal",
        tokenKindID: 1,
        mode: .emit,
        family: .literal,
        priorityRank: 0,
        minWidth: 2,
        maxWidth: 2,
        firstClassSetID: 0,
        plan: .literal(bytes: Array("ab".utf8))
      )
    ],
    keywordRemaps: []
  )

  return try ArtifactRuntime.fromArtifact(artifact)
}
