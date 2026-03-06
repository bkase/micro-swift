import MLX
import MicroSwiftLexerGen

public struct ClassSetRuntime: @unchecked Sendable {
  /// Dense mask bytes in row-major order: [numClassSets, numByteClasses].
  /// 1 means member, 0 means non-member.
  public let mask: MLXArray
  private let hostMaskBytesStorage: [UInt8]
  public let numClassSets: Int
  public let numByteClasses: Int

  /// Check if classID belongs to classSet setID
  public func contains(setID: UInt16, classID: UInt8) -> Bool {
    guard Int(setID) < numClassSets, Int(classID) < numByteClasses else { return false }
    let flatIndex = Int(setID) * numByteClasses + Int(classID)
    return hostMaskBytes()[flatIndex] != 0
  }

  public func hostMaskBytes() -> [UInt8] {
    hostMaskBytesStorage
  }

  public init(
    mask: MLXArray,
    numClassSets: Int,
    numByteClasses: Int,
    hostMaskBytesStorage: [UInt8]? = nil
  ) {
    self.mask = mask
    self.numClassSets = numClassSets
    self.numByteClasses = numByteClasses
    self.hostMaskBytesStorage = hostMaskBytesStorage ?? withMLXCPU { mask.asArray(UInt8.self) }
  }

  public init(mask: [[Bool]], numClassSets: Int, numByteClasses: Int) {
    var flatMask = Array(repeating: UInt8(0), count: numClassSets * numByteClasses)
    for setIndex in 0..<min(mask.count, numClassSets) {
      for classIndex in 0..<min(mask[setIndex].count, numByteClasses) where mask[setIndex][classIndex]
      {
        flatMask[(setIndex * numByteClasses) + classIndex] = 1
      }
    }
    self.init(
      mask: withMLXCPU { MLXArray(flatMask, [numClassSets, numByteClasses]) },
      numClassSets: numClassSets,
      numByteClasses: numByteClasses,
      hostMaskBytesStorage: flatMask
    )
  }

  /// Build from artifact's classSets and classes
  public static func build(classSets: [ClassSetDecl], classes: [ByteClassDecl]) -> ClassSetRuntime {
    let maxSetID = classSets.map { Int($0.classSetID.rawValue) }.max() ?? -1
    let maxClassID = classes.map { Int($0.classID) }.max() ?? -1
    let numClassSets = max(classSets.count, maxSetID + 1)
    let numByteClasses = max(classes.count, maxClassID + 1)

    var mask = Array(repeating: UInt8(0), count: numClassSets * numByteClasses)

    for set in classSets {
      let setIndex = Int(set.classSetID.rawValue)
      guard setIndex < numClassSets else { continue }
      for classID in set.classes {
        let classIndex = Int(classID)
        guard classIndex < numByteClasses else { continue }
        mask[(setIndex * numByteClasses) + classIndex] = 1
      }
    }

    return ClassSetRuntime(
      mask: withMLXCPU { MLXArray(mask, [numClassSets, numByteClasses]) },
      numClassSets: numClassSets,
      numByteClasses: numByteClasses,
      hostMaskBytesStorage: mask
    )
  }
}
