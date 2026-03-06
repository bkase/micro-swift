import Testing

@testable import MicroSwiftTensorCore

@Suite
struct LiteralExecutionTests {
  @Test
  func singleLiteralFoundAtCorrectPositions() {
    let bytes = Array("a==b==".utf8)
    let validMask = Array(repeating: true, count: bytes.count)

    let result = LiteralExecution.evaluateLiteral(
      bytes: bytes,
      validMask: validMask,
      literalBytes: Array("==".utf8)
    )

    #expect(result == [0, 2, 0, 0, 2, 0])
  }

  @Test
  func literalAtEndNotMatchedWhenExceedingValidRegion() {
    let bytes = Array("abc==".utf8)
    let validMask: [Bool] = [true, true, true, true, false]

    let result = LiteralExecution.evaluateLiteral(
      bytes: bytes,
      validMask: validMask,
      literalBytes: Array("==".utf8)
    )

    #expect(result == [0, 0, 0, 0, 0])
  }

  @Test
  func multipleSameLengthLiteralsInBucket() {
    let bytes = Array("a==!=<=".utf8)
    let validMask = Array(repeating: true, count: bytes.count)
    let rules: [(ruleIndex: Int, literalBytes: [UInt8])] = [
      (ruleIndex: 10, literalBytes: Array("==".utf8)),
      (ruleIndex: 11, literalBytes: Array("!=".utf8)),
      (ruleIndex: 12, literalBytes: Array("<=".utf8)),
    ]

    let results = LiteralExecution.evaluateLiteralBucket(
      bytes: bytes,
      validMask: validMask,
      rules: rules
    )

    #expect(results.count == 3)
    #expect(results[0] == [0, 2, 0, 0, 0, 0, 0])
    #expect(results[1] == [0, 0, 0, 2, 0, 0, 0])
    #expect(results[2] == [0, 0, 0, 0, 0, 2, 0])
  }

  @Test
  func literalNotFoundReturnsAllZeros() {
    let bytes = Array("abcdef".utf8)
    let validMask = Array(repeating: true, count: bytes.count)

    let result = LiteralExecution.evaluateLiteral(
      bytes: bytes,
      validMask: validMask,
      literalBytes: Array("==".utf8)
    )

    #expect(result == [0, 0, 0, 0, 0, 0])
  }

  @Test
  func overlappingLiteralsAreDetected() {
    let bytes = Array("===".utf8)
    let validMask = Array(repeating: true, count: bytes.count)

    let result = LiteralExecution.evaluateLiteral(
      bytes: bytes,
      validMask: validMask,
      literalBytes: Array("==".utf8)
    )

    #expect(result == [2, 2, 0])
  }
}
