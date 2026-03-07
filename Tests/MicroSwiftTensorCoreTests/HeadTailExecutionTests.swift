import MLX
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct HeadTailExecutionTests {
  @Test(.enabled(if: requiresMLXEval))
  func usesMetalBackend() {
    #expect(HeadTailExecution.backendNameForTesting().starts(with: "metal-"))
  }

  @Test(.enabled(if: requiresMLXEval))
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

  @Test(.enabled(if: requiresMLXEval))
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

  @Test(.enabled(if: requiresMLXEval))
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

  @Test(.enabled(if: requiresMLXEval))
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

  @Test(.enabled(if: requiresMLXEval))
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
      [false, true, false],  // head: [a-zA-Z_]
      [false, true, true],  // tail: [a-zA-Z0-9_]
    ]
    return ClassSetRuntime(mask: mask, numClassSets: 2, numByteClasses: 3)
  }

  // MARK: - MLX differential tests

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForIdentifierFoo() {
    let runtime = makeIdentifierRuntime()
    assertMLXMatchesHost(
      classIDs: [1, 1, 1], validMask: [true, true, true],
      headClassSetID: 0, tailClassSetID: 1, runtime: runtime
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForIdentifierX1() {
    let runtime = makeIdentifierRuntime()
    assertMLXMatchesHost(
      classIDs: [1, 2], validMask: [true, true],
      headClassSetID: 0, tailClassSetID: 1, runtime: runtime
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForNonHeadStart() {
    let runtime = makeIdentifierRuntime()
    assertMLXMatchesHost(
      classIDs: [2, 1, 1], validMask: [true, true, true],
      headClassSetID: 0, tailClassSetID: 1, runtime: runtime
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForTwoIdentifiers() {
    let runtime = makeIdentifierRuntime()
    assertMLXMatchesHost(
      classIDs: [1, 1, 0, 1, 2], validMask: [true, true, true, true, true],
      headClassSetID: 0, tailClassSetID: 1, runtime: runtime
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForSingleCharIdentifier() {
    let runtime = makeIdentifierRuntime()
    assertMLXMatchesHost(
      classIDs: [1], validMask: [true],
      headClassSetID: 0, tailClassSetID: 1, runtime: runtime
    )
  }

  private func assertMLXMatchesHost(
    classIDs: [UInt8],
    validMask: [Bool],
    headClassSetID: UInt16,
    tailClassSetID: UInt16,
    runtime: ClassSetRuntime
  ) {
    let hostResult = HeadTailExecution.evaluateHeadTail(
      classIDs: classIDs,
      validMask: validMask,
      headClassSetID: headClassSetID,
      tailClassSetID: tailClassSetID,
      classSetRuntime: runtime
    )
    let classIDTensor = withMLXCPU {
      MLXArray(classIDs.map { UInt16($0) }, [classIDs.count]).asType(.uint16)
    }
    let validMaskTensor = withMLXCPU {
      MLXArray(validMask, [validMask.count]).asType(.bool)
    }
    let mlxResult = HeadTailExecution.evaluateHeadTailMLX(
      classIDTensor: classIDTensor,
      validMaskTensor: validMaskTensor,
      headClassSetID: headClassSetID,
      tailClassSetID: tailClassSetID,
      classSetRuntime: runtime
    )
    let mlxHost = mlxResult.asType(.uint16).asArray(UInt16.self)
    #expect(mlxHost == hostResult)
  }
}
