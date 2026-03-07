import Foundation
import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct MembershipKernelTests {
  @Test(.enabled(if: requiresMLXEval))
  func membershipMaskMatchesClassSetContents() throws {
    let classSets = try decodeClassSets(
      """
      [
        {"classSetID": {"rawValue": 0}, "classes": [1, 3]}
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

    let classIDs: [UInt8] = [0, 1, 3, 2, 1]
    let mask = MembershipKernels.membershipMask(
      classIDs: classIDs, setID: 0, classSetRuntime: runtime)

    #expect(mask == [false, true, true, false, true])
  }

  @Test(.enabled(if: requiresMLXEval))
  func precomputeReturnsCorrectNumberOfMasks() throws {
    let classSets = try decodeClassSets(
      """
      [
        {"classSetID": {"rawValue": 0}, "classes": [0]},
        {"classSetID": {"rawValue": 1}, "classes": [1]}
      ]
      """
    )
    let classes = try decodeByteClasses(
      """
      [
        {"classID": 0, "bytes": [0]},
        {"classID": 1, "bytes": [1]}
      ]
      """
    )
    let runtime = ClassSetRuntime.build(classSets: classSets, classes: classes)

    let classIDs: [UInt8] = [0, 1, 0]
    let masks = MembershipKernels.precomputeMasks(
      classIDs: classIDs,
      setIDs: [0, 1],
      classSetRuntime: runtime
    )

    #expect(masks.count == 2)
    #expect(masks[0] == [true, false, true])
    #expect(masks[1] == [false, true, false])
  }

  private func decodeClassSets(_ json: String) throws -> [ClassSetDecl] {
    try JSONDecoder().decode([ClassSetDecl].self, from: Data(json.utf8))
  }

  private func decodeByteClasses(_ json: String) throws -> [ByteClassDecl] {
    try JSONDecoder().decode([ByteClassDecl].self, from: Data(json.utf8))
  }
}
