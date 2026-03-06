import Testing
@testable import MicroSwiftTensorCore

@Suite
struct PrefixedExecutionTests {
  private let bodySetID: UInt16 = 0
  private let stopSetID: UInt16 = 1

  @Test
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

  @Test
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

  @Test
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

  @Test
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

  @Test
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
}
