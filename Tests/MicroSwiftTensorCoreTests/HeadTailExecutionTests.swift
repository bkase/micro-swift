import Testing
@testable import MicroSwiftTensorCore

@Suite
struct HeadTailExecutionTests {
  @Test
  func identifierFooReturnsLengthThree() {
    let runtime = makeIdentifierRuntime()
    let classIDs: [UInt8] = [1, 1, 1]
    let validMask = [true, true, true]

    let result = HeadTailExecution.evaluateHeadTail(
      classIDs: classIDs,
      validMask: validMask,
      headClassSetID: 0,
      tailClassSetID: 1,
      classSetRuntime: runtime
    )

    #expect(result == [3, 0, 0])
  }

  @Test
  func identifierX1ReturnsLengthTwo() {
    let runtime = makeIdentifierRuntime()
    let classIDs: [UInt8] = [1, 2]
    let validMask = [true, true]

    let result = HeadTailExecution.evaluateHeadTail(
      classIDs: classIDs,
      validMask: validMask,
      headClassSetID: 0,
      tailClassSetID: 1,
      classSetRuntime: runtime
    )

    #expect(result == [2, 0])
  }

  @Test
  func nonHeadByteDoesNotStartMatch() {
    let runtime = makeIdentifierRuntime()
    let classIDs: [UInt8] = [2, 1, 1]
    let validMask = [true, true, true]

    let result = HeadTailExecution.evaluateHeadTail(
      classIDs: classIDs,
      validMask: validMask,
      headClassSetID: 0,
      tailClassSetID: 1,
      classSetRuntime: runtime
    )

    #expect(result == [0, 0, 0])
  }

  @Test
  func twoIdentifiersSeparatedBySpace() {
    let runtime = makeIdentifierRuntime()
    let classIDs: [UInt8] = [1, 1, 0, 1, 2]
    let validMask = [true, true, true, true, true]

    let result = HeadTailExecution.evaluateHeadTail(
      classIDs: classIDs,
      validMask: validMask,
      headClassSetID: 0,
      tailClassSetID: 1,
      classSetRuntime: runtime
    )

    #expect(result == [2, 0, 0, 2, 0])
  }

  @Test
  func singleCharIdentifier() {
    let runtime = makeIdentifierRuntime()
    let classIDs: [UInt8] = [1]
    let validMask = [true]

    let result = HeadTailExecution.evaluateHeadTail(
      classIDs: classIDs,
      validMask: validMask,
      headClassSetID: 0,
      tailClassSetID: 1,
      classSetRuntime: runtime
    )

    #expect(result == [1])
  }

  /// classIDs used by tests:
  /// 0 = space, 1 = letterOrUnderscore, 2 = digit
  private func makeIdentifierRuntime() -> ClassSetRuntime {
    let mask: [[Bool]] = [
      [false, true, false], // head: [a-zA-Z_]
      [false, true, true], // tail: [a-zA-Z0-9_]
    ]
    return ClassSetRuntime(mask: mask, numClassSets: 2, numByteClasses: 3)
  }
}
