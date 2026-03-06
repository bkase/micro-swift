public struct ClassSetID: Sendable, Equatable, Hashable, Codable {
  public let rawValue: UInt16

  public init(_ rawValue: UInt16) {
    self.rawValue = rawValue
  }
}

public struct ClassSetDecl: Sendable, Equatable, Codable {
  public let classSetID: ClassSetID
  public let classes: [UInt8] // strictly ascending, unique
}

public struct ClassSets: Sendable, Equatable {
  public let classSets: [ClassSetDecl]
  private let idsByClassMembers: [ClassKey: ClassSetID]

  init(classSets: [ClassSetDecl]) {
    self.classSets = classSets
    var idsByClassMembers: [ClassKey: ClassSetID] = [:]
    for set in classSets {
      idsByClassMembers[ClassKey(set.classes)] = set.classSetID
    }
    self.idsByClassMembers = idsByClassMembers
  }

  public func classSetID(for byteSet: ByteSet, in byteClasses: ByteClasses) -> ClassSetID? {
    let members = projectedClasses(for: byteSet, in: byteClasses)
    return idsByClassMembers[ClassKey(members)]
  }
}

extension ValidatedSpec {
  public func buildClassSets(using byteClasses: ByteClasses) -> ClassSets {
    let relevantByteSets = relevantByteSetsForLowering()
    var projected: Set<ClassKey> = []

    for byteSet in relevantByteSets {
      projected.insert(ClassKey(projectedClasses(for: byteSet, in: byteClasses)))
    }

    let sortedClassSets = projected
      .map(\.classes)
      .sorted { lhs, rhs in
        lhs.lexicographicallyPrecedes(rhs)
      }

    let decls = sortedClassSets.enumerated().map { index, classes in
      ClassSetDecl(classSetID: ClassSetID(UInt16(index)), classes: classes)
    }
    return ClassSets(classSets: decls)
  }
}

func projectedClasses(for byteSet: ByteSet, in byteClasses: ByteClasses) -> [UInt8] {
  var set = Set<UInt8>()
  for byte in byteSet.members {
    set.insert(byteClasses.byteToClass[Int(byte)])
  }
  return set.sorted()
}

private struct ClassKey: Sendable, Hashable {
  let classes: [UInt8]

  init(_ classes: [UInt8]) {
    self.classes = classes
  }
}
