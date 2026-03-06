import MicroSwiftLexerGen

public struct ClassSetRuntime: Sendable {
  /// Dense mask: classSetMask[setID][classID] -> Bool
  /// Dimensions: [numClassSets, numByteClasses]
  public let mask: [[Bool]]
  public let numClassSets: Int
  public let numByteClasses: Int

  /// Check if classID belongs to classSet setID
  public func contains(setID: UInt16, classID: UInt8) -> Bool {
    guard Int(setID) < numClassSets, Int(classID) < numByteClasses else { return false }
    return mask[Int(setID)][Int(classID)]
  }

  /// Build from artifact's classSets and classes
  public static func build(classSets: [ClassSetDecl], classes: [ByteClassDecl]) -> ClassSetRuntime {
    let maxSetID = classSets.map { Int($0.classSetID.rawValue) }.max() ?? -1
    let maxClassID = classes.map { Int($0.classID) }.max() ?? -1
    let numClassSets = max(classSets.count, maxSetID + 1)
    let numByteClasses = max(classes.count, maxClassID + 1)

    var mask = Array(
      repeating: Array(repeating: false, count: numByteClasses),
      count: numClassSets
    )

    for set in classSets {
      let setIndex = Int(set.classSetID.rawValue)
      guard setIndex < numClassSets else { continue }
      for classID in set.classes {
        let classIndex = Int(classID)
        guard classIndex < numByteClasses else { continue }
        mask[setIndex][classIndex] = true
      }
    }

    return ClassSetRuntime(mask: mask, numClassSets: numClassSets, numByteClasses: numByteClasses)
  }
}
