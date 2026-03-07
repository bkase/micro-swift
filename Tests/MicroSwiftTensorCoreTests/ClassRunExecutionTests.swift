import Foundation
import MLX
import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct ClassRunExecutionTests {
  @Test(.enabled(if: requiresMLXEval))
  func usesMetalBackend() {
    #expect(ClassRunExecution.backendNameForTesting().starts(with: "metal-"))
  }

  @Test(.enabled(if: requiresMLXEval))
  func singleDigitRunFoundAtStart() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [1, 1, 1, 0]
    let validMask: [Bool] = [true, true, true, true]

    let candidateLengths = ClassRunExecution.evaluateClassRun(
      classIDs: classIDs,
      validMask: validMask,
      bodyClassSetID: 0,
      minLength: 1,
      classSetRuntime: runtime
    )

    #expect(candidateLengths == [3, 0, 0, 0])
  }

  @Test(.enabled(if: requiresMLXEval))
  func whitespaceRunFoundWithMinLengthOne() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [0, 2, 2, 2, 0]
    let validMask: [Bool] = [true, true, true, true, true]

    let candidateLengths = ClassRunExecution.evaluateClassRun(
      classIDs: classIDs,
      validMask: validMask,
      bodyClassSetID: 1,
      minLength: 1,
      classSetRuntime: runtime
    )

    #expect(candidateLengths == [0, 3, 0, 0, 0])
  }

  @Test(.enabled(if: requiresMLXEval))
  func runBelowMinLengthIsFilteredOut() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [0, 1, 1, 0]
    let validMask: [Bool] = [true, true, true, true]

    let candidateLengths = ClassRunExecution.evaluateClassRun(
      classIDs: classIDs,
      validMask: validMask,
      bodyClassSetID: 0,
      minLength: 3,
      classSetRuntime: runtime
    )

    #expect(candidateLengths == [0, 0, 0, 0])
  }

  @Test(.enabled(if: requiresMLXEval))
  func multipleSeparateRunsAreDetected() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [1, 1, 0, 1, 1, 1, 0, 1]
    let validMask: [Bool] = [true, true, true, true, true, true, true, true]

    let candidateLengths = ClassRunExecution.evaluateClassRun(
      classIDs: classIDs,
      validMask: validMask,
      bodyClassSetID: 0,
      minLength: 1,
      classSetRuntime: runtime
    )

    #expect(candidateLengths == [2, 0, 0, 3, 0, 0, 0, 1])
  }

  @Test(.enabled(if: requiresMLXEval))
  func runStopsAtValidLengthBoundary() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [1, 1, 1, 1, 1]
    let validMask: [Bool] = [true, true, true, false, false]

    let candidateLengths = ClassRunExecution.evaluateClassRun(
      classIDs: classIDs,
      validMask: validMask,
      bodyClassSetID: 0,
      minLength: 1,
      classSetRuntime: runtime
    )

    #expect(candidateLengths == [3, 0, 0, 0, 0])
  }

  private func makeRuntime() throws -> ClassSetRuntime {
    let classSets = try decodeClassSets(
      """
      [
        {"classSetID": {"rawValue": 0}, "classes": [1]},
        {"classSetID": {"rawValue": 1}, "classes": [2]}
      ]
      """
    )
    let classes = try decodeByteClasses(
      """
      [
        {"classID": 0, "bytes": [65]},
        {"classID": 1, "bytes": [48]},
        {"classID": 2, "bytes": [32]}
      ]
      """
    )

    return ClassSetRuntime.build(classSets: classSets, classes: classes)
  }

  private func decodeClassSets(_ json: String) throws -> [ClassSetDecl] {
    try JSONDecoder().decode([ClassSetDecl].self, from: Data(json.utf8))
  }

  private func decodeByteClasses(_ json: String) throws -> [ByteClassDecl] {
    try JSONDecoder().decode([ByteClassDecl].self, from: Data(json.utf8))
  }

  // MARK: - MLX differential tests

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForSingleRun() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [1, 1, 1, 0]
    let validMask: [Bool] = [true, true, true, true]
    try assertMLXMatchesHost(
      classIDs: classIDs, validMask: validMask,
      bodyClassSetID: 0, minLength: 1, runtime: runtime
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostForMultipleRuns() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [1, 1, 0, 1, 1, 1, 0, 1]
    let validMask: [Bool] = [true, true, true, true, true, true, true, true]
    try assertMLXMatchesHost(
      classIDs: classIDs, validMask: validMask,
      bodyClassSetID: 0, minLength: 1, runtime: runtime
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostWithMinLengthFilter() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [0, 1, 1, 0]
    let validMask: [Bool] = [true, true, true, true]
    try assertMLXMatchesHost(
      classIDs: classIDs, validMask: validMask,
      bodyClassSetID: 0, minLength: 3, runtime: runtime
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostWithValidLengthBoundary() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [1, 1, 1, 1, 1]
    let validMask: [Bool] = [true, true, true, false, false]
    try assertMLXMatchesHost(
      classIDs: classIDs, validMask: validMask,
      bodyClassSetID: 0, minLength: 1, runtime: runtime
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mlxMatchesHostWhitespaceRun() throws {
    let runtime = try makeRuntime()
    let classIDs: [UInt8] = [0, 2, 2, 2, 0]
    let validMask: [Bool] = [true, true, true, true, true]
    try assertMLXMatchesHost(
      classIDs: classIDs, validMask: validMask,
      bodyClassSetID: 1, minLength: 1, runtime: runtime
    )
  }

  private func assertMLXMatchesHost(
    classIDs: [UInt8],
    validMask: [Bool],
    bodyClassSetID: UInt16,
    minLength: UInt16,
    runtime: ClassSetRuntime
  ) throws {
    let hostResult = ClassRunExecution.evaluateClassRun(
      classIDs: classIDs,
      validMask: validMask,
      bodyClassSetID: bodyClassSetID,
      minLength: minLength,
      classSetRuntime: runtime
    )
    let classIDTensor = MLXArray(classIDs.map { UInt16($0) }, [classIDs.count]).asType(.uint16)
    let validMaskTensor = MLXArray(validMask, [validMask.count]).asType(.bool)
    let mlxResult = ClassRunExecution.evaluateClassRunMLX(
      classIDTensor: classIDTensor,
      validMaskTensor: validMaskTensor,
      bodyClassSetID: bodyClassSetID,
      minLength: minLength,
      classSetRuntime: runtime
    )
    let mlxHost = mlxResult.asType(.uint16).asArray(UInt16.self)
    #expect(mlxHost == hostResult)
  }
}
