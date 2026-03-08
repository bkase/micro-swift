import MLX
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct PrefixedExecutionTests {
  private let bodySetID: UInt16 = 0
  private let stopSetID: UInt16 = 1

  @Test(.enabled(if: requiresMLXEval))
  func lineCommentStopsBeforeNewline() {
    let bytes = Array("// hello\n".utf8)
    let validMask = Array(repeating: true, count: bytes.count)
    let classIDs = classify(bytes)
    let runtime = makeRuntime()
    let nextStop = makeNextStop(
      classIDs: classIDs,
      validMask: validMask,
      runtime: runtime
    )

    let lengths = PrefixedExecution.evaluatePrefixed(
      bytes: bytes,
      classIDs: classIDs,
      validMask: validMask,
      prefix: Array("//".utf8),
      bodyClassSetID: bodySetID,
      stopClassSetID: stopSetID,
      classSetRuntime: runtime,
      nextStop: nextStop
    )

    #expect(lengths[0] == 8)
    #expect(lengths.dropFirst().allSatisfy { $0 == 0 })
  }

  @Test(.enabled(if: requiresMLXEval))
  func lineCommentAtEndConsumesToValidRegionEnd() {
    let bytes = Array("// hi".utf8)
    let validMask = Array(repeating: true, count: bytes.count)
    let classIDs = classify(bytes)
    let runtime = makeRuntime()
    let nextStop = makeNextStop(
      classIDs: classIDs,
      validMask: validMask,
      runtime: runtime
    )

    let lengths = PrefixedExecution.evaluatePrefixed(
      bytes: bytes,
      classIDs: classIDs,
      validMask: validMask,
      prefix: Array("//".utf8),
      bodyClassSetID: bodySetID,
      stopClassSetID: stopSetID,
      classSetRuntime: runtime,
      nextStop: nextStop
    )

    #expect(lengths[0] == 5)
  }

  @Test(.enabled(if: requiresMLXEval))
  func noPrefixMatchProducesAllZeros() {
    let bytes = Array("abc\n".utf8)
    let validMask = Array(repeating: true, count: bytes.count)
    let classIDs = classify(bytes)
    let runtime = makeRuntime()
    let nextStop = makeNextStop(
      classIDs: classIDs,
      validMask: validMask,
      runtime: runtime
    )

    let lengths = PrefixedExecution.evaluatePrefixed(
      bytes: bytes,
      classIDs: classIDs,
      validMask: validMask,
      prefix: Array("//".utf8),
      bodyClassSetID: bodySetID,
      stopClassSetID: stopSetID,
      classSetRuntime: runtime,
      nextStop: nextStop
    )

    #expect(lengths.allSatisfy { $0 == 0 })
  }

  @Test(.enabled(if: requiresMLXEval))
  func multipleLineCommentsAreEvaluatedIndependently() {
    let bytes = Array("//a\nx//bc\n".utf8)
    let validMask = Array(repeating: true, count: bytes.count)
    let classIDs = classify(bytes)
    let runtime = makeRuntime()
    let nextStop = makeNextStop(
      classIDs: classIDs,
      validMask: validMask,
      runtime: runtime
    )

    let lengths = PrefixedExecution.evaluatePrefixed(
      bytes: bytes,
      classIDs: classIDs,
      validMask: validMask,
      prefix: Array("//".utf8),
      bodyClassSetID: bodySetID,
      stopClassSetID: stopSetID,
      classSetRuntime: runtime,
      nextStop: nextStop
    )

    #expect(lengths[0] == 3)
    #expect(lengths[5] == 4)
  }

  @Test(.enabled(if: requiresMLXEval))
  func prefixWithoutBodyReturnsPrefixLength() {
    let bytes = Array("//\n".utf8)
    let validMask = Array(repeating: true, count: bytes.count)
    let classIDs = classify(bytes)
    let runtime = makeRuntime()
    let nextStop = makeNextStop(
      classIDs: classIDs,
      validMask: validMask,
      runtime: runtime
    )

    let lengths = PrefixedExecution.evaluatePrefixed(
      bytes: bytes,
      classIDs: classIDs,
      validMask: validMask,
      prefix: Array("//".utf8),
      bodyClassSetID: bodySetID,
      stopClassSetID: stopSetID,
      classSetRuntime: runtime,
      nextStop: nextStop
    )

    #expect(lengths[0] == 2)
  }

  private func makeRuntime() -> ClassSetRuntime {
    let bodyRow = [true, true, false, true]
    let stopRow = [false, false, true, false]
    return ClassSetRuntime(mask: [bodyRow, stopRow], numClassSets: 2, numByteClasses: 4)
  }

  private func makeNextStop(
    classIDs: [UInt8],
    validMask: [Bool],
    runtime: ClassSetRuntime
  ) -> [Int32] {
    let stopMask = zip(classIDs, validMask).map { classID, isValid in
      isValid && runtime.contains(setID: stopSetID, classID: classID)
    }
    let validLen = Int32(validMask.prefix { $0 }.count)
    return NextStopHelper.computeNextStop(stopMask: stopMask, validLen: validLen)
  }

  private func classify(_ bytes: [UInt8]) -> [UInt8] {
    bytes.map { byte in
      if byte == UInt8(ascii: "/") { return 0 }
      if byte == UInt8(ascii: "\n") { return 2 }
      if byte == UInt8(ascii: " ") { return 3 }
      return 1
    }
  }

  // MARK: - MLX differential tests

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForLineComment() {
    assertMLXMatchesHost(
      text: "// hello\n",
      prefix: Array("//".utf8),
      bodySetID: bodySetID,
      stopSetID: stopSetID
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForCommentAtEnd() {
    assertMLXMatchesHost(
      text: "// hi",
      prefix: Array("//".utf8),
      bodySetID: bodySetID,
      stopSetID: stopSetID
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForNoMatch() {
    assertMLXMatchesHost(
      text: "abc\n",
      prefix: Array("//".utf8),
      bodySetID: bodySetID,
      stopSetID: stopSetID
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForMultipleComments() {
    assertMLXMatchesHost(
      text: "//a\nx//bc\n",
      prefix: Array("//".utf8),
      bodySetID: bodySetID,
      stopSetID: stopSetID
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForPrefixWithoutBody() {
    assertMLXMatchesHost(
      text: "//\n",
      prefix: Array("//".utf8),
      bodySetID: bodySetID,
      stopSetID: stopSetID
    )
  }

  private func assertMLXMatchesHost(
    text: String,
    prefix: [UInt8],
    bodySetID: UInt16,
    stopSetID: UInt16?
  ) {
    let bytes = Array(text.utf8)
    let validMask = Array(repeating: true, count: bytes.count)
    let classIDs = classify(bytes)
    let runtime = makeRuntime()
    let nextStop = makeNextStop(
      classIDs: classIDs,
      validMask: validMask,
      runtime: runtime
    )

    let hostResult = PrefixedExecution.evaluatePrefixed(
      bytes: bytes,
      classIDs: classIDs,
      validMask: validMask,
      prefix: prefix,
      bodyClassSetID: bodySetID,
      stopClassSetID: stopSetID,
      classSetRuntime: runtime,
      nextStop: nextStop
    )

    let pageLen = bytes.count
    let byteTensor = MLXArray(bytes, [pageLen]).asType(.uint8)
    let classIDTensor = MLXArray(classIDs.map { UInt16($0) }, [pageLen]).asType(.uint16)
    let validMaskTensor = MLXArray(validMask, [pageLen]).asType(.bool)

    // Precompute nextInvalidTensor
    let indices = MLXArray(Int32(0)..<Int32(pageLen), [pageLen])
    let sentinelFill = MLXArray(Array(repeating: Int32(pageLen), count: pageLen), [pageLen])
    let invalidIndices = which(.!validMaskTensor, indices, sentinelFill)
    let nextInvalidTensor = cummin(invalidIndices, axis: 0, reverse: true)

    // Precompute nextStopTensor
    let nextStopTensor: MLXArray?
    if let stopSetID {
      let stopMember = MembershipKernels.membershipMaskTensor(
        classIDTensor: classIDTensor,
        setID: stopSetID,
        classSetRuntime: runtime
      )
      let isStop = stopMember .&& validMaskTensor
      let stopIndices = which(isStop, indices, sentinelFill)
      nextStopTensor = cummin(stopIndices, axis: 0, reverse: true)
    } else {
      nextStopTensor = nil
    }

    let mlxResult = PrefixedExecution.evaluatePrefixedMLX(
      byteTensor: byteTensor,
      classIDTensor: classIDTensor,
      validMaskTensor: validMaskTensor,
      prefix: prefix,
      bodyClassSetID: bodySetID,
      classSetRuntime: runtime,
      nextInvalidTensor: nextInvalidTensor,
      nextStopTensor: nextStopTensor
    )
    let mlxHost = mlxResult.asType(.uint16).asArray(UInt16.self)
    #expect(mlxHost == hostResult)
  }
}
