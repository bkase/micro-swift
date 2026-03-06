import MicroSwiftLexerGen

public struct ArtifactRuntime: Sendable {
  public let specName: String
  public let ruleCount: Int

  // Runtime hint constants
  public let maxLiteralLength: UInt16
  public let maxBoundedRuleWidth: UInt16
  public let maxDeterministicLookaheadBytes: UInt16

  // Byte-to-class LUT [256]
  public let byteToClassLUT: [UInt8]

  // Token kinds indexed by tokenKindID
  public let tokenKinds: [TokenKindDecl]

  // All lowered rules
  public let rules: [LoweredRule]

  // Keyword remap tables
  public let keywordRemaps: [KeywordRemapTable]

  // ClassSet declarations (for P6 to expand into membership masks)
  public let classSets: [ClassSetDecl]

  // Byte class declarations
  public let classes: [ByteClassDecl]

  // Dense class-set membership runtime table
  public let classSetRuntime: ClassSetRuntime

  public init(
    specName: String,
    ruleCount: Int,
    maxLiteralLength: UInt16,
    maxBoundedRuleWidth: UInt16,
    maxDeterministicLookaheadBytes: UInt16,
    byteToClassLUT: [UInt8],
    tokenKinds: [TokenKindDecl],
    rules: [LoweredRule],
    keywordRemaps: [KeywordRemapTable],
    classSets: [ClassSetDecl],
    classes: [ByteClassDecl]
  ) {
    self.specName = specName
    self.ruleCount = ruleCount
    self.maxLiteralLength = maxLiteralLength
    self.maxBoundedRuleWidth = maxBoundedRuleWidth
    self.maxDeterministicLookaheadBytes = maxDeterministicLookaheadBytes
    self.byteToClassLUT = byteToClassLUT
    self.tokenKinds = tokenKinds
    self.rules = rules
    self.keywordRemaps = keywordRemaps
    self.classSets = classSets
    self.classes = classes
    self.classSetRuntime = ClassSetRuntime.build(classSets: classSets, classes: classes)
  }
}
