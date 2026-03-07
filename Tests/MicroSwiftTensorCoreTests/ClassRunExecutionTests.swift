import Foundation
import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct ClassRunExecutionTests {
  @Test
  func usesMetalBackend() {
    #expect(ClassRunExecution.backendNameForTesting().starts(with: "metal-"))
  }

  @Test
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

  @Test
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

  @Test
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

  @Test
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

  @Test
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
}
