import Foundation
import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct ClassSetRuntimeTests {
  @Test
  func buildsDenseMaskAndAnswersMembership() throws {
    let classSets = try decodeClassSets(
      """
      [
        {"classSetID": {"rawValue": 0}, "classes": [0, 2]},
        {"classSetID": {"rawValue": 1}, "classes": [1]}
      ]
      """
    )
    let classes = try decodeByteClasses(
      """
      [
        {"classID": 0, "bytes": [48]},
        {"classID": 1, "bytes": [65]},
        {"classID": 2, "bytes": [95]}
      ]
      """
    )

    let runtime = ClassSetRuntime.build(classSets: classSets, classes: classes)

    #expect(runtime.numClassSets == 2)
    #expect(runtime.numByteClasses == 3)
    #expect(runtime.contains(setID: 0, classID: 0))
    #expect(runtime.contains(setID: 0, classID: 2))
    #expect(!runtime.contains(setID: 0, classID: 1))
    #expect(runtime.contains(setID: 1, classID: 1))
  }

  @Test
  func emptyClassSetsProduceEmptyMask() {
    let runtime = ClassSetRuntime.build(classSets: [], classes: [])

    #expect(runtime.numClassSets == 0)
    #expect(runtime.numByteClasses == 0)
    #expect(runtime.hostMaskBytes().isEmpty)
    #expect(!runtime.contains(setID: 0, classID: 0))
  }

  @Test
  func supportsBoundaryClassIDAtUpperEdge() throws {
    let classSets = try decodeClassSets(
      """
      [
        {"classSetID": {"rawValue": 0}, "classes": [3]}
      ]
      """
    )
    let classes = try decodeByteClasses(
      """
      [
        {"classID": 0, "bytes": [0]},
        {"classID": 1, "bytes": [1]},
        {"classID": 2, "bytes": [2]},
        {"classID": 3, "bytes": [3]}
      ]
      """
    )

    let runtime = ClassSetRuntime.build(classSets: classSets, classes: classes)

    #expect(runtime.numByteClasses == 4)
    #expect(runtime.contains(setID: 0, classID: 3))
    #expect(!runtime.contains(setID: 0, classID: 4))
  }

  private func decodeClassSets(_ json: String) throws -> [ClassSetDecl] {
    try JSONDecoder().decode([ClassSetDecl].self, from: Data(json.utf8))
  }

  private func decodeByteClasses(_ json: String) throws -> [ByteClassDecl] {
    try JSONDecoder().decode([ByteClassDecl].self, from: Data(json.utf8))
  }
}
