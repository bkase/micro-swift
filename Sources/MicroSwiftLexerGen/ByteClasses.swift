public struct ByteClassDecl: Sendable, Equatable, Codable {
  public let classID: UInt8
  public let bytes: [UInt8]
}

public struct ByteClasses: Sendable, Equatable, Codable {
  public let byteToClass: [UInt8] // length 256
  public let classes: [ByteClassDecl]
}

extension ValidatedSpec {
  public func buildByteClasses() -> ByteClasses {
    let predicates = relevantByteSetsForLowering()
    var groups: [Signature: [UInt8]] = [:]

    for byte in UInt8.min...UInt8.max {
      let signature = Signature(byte: byte, predicates: predicates)
      groups[signature, default: []].append(byte)
    }

    let sortedGroups = groups.values.sorted { lhs, rhs in
      if lhs[0] != rhs[0] { return lhs[0] < rhs[0] }
      return lhs.lexicographicallyPrecedes(rhs)
    }

    var byteToClass = Array(repeating: UInt8(0), count: 256)
    var classes: [ByteClassDecl] = []
    classes.reserveCapacity(sortedGroups.count)

    for (index, members) in sortedGroups.enumerated() {
      let classID = UInt8(index)
      classes.append(ByteClassDecl(classID: classID, bytes: members))
      for byte in members {
        byteToClass[Int(byte)] = classID
      }
    }

    return ByteClasses(byteToClass: byteToClass, classes: classes)
  }

  func relevantByteSetsForLowering() -> [ByteSet] {
    var allSets: [ByteSet] = []
    for rule in rules {
      allSets.append(rule.props.firstByteSet)
      allSets.append(contentsOf: rule.regex.primitiveByteSets)
    }

    let sortedUnique = Set(allSets).sorted {
      let lm = $0.members
      let rm = $1.members
      if lm.count != rm.count { return lm.count < rm.count }
      return lm.lexicographicallyPrecedes(rm)
    }
    return sortedUnique
  }
}

private struct Signature: Hashable {
  private let words: [UInt64]

  init(byte: UInt8, predicates: [ByteSet]) {
    var words = Array(repeating: UInt64(0), count: (predicates.count + 63) / 64)
    for (index, set) in predicates.enumerated() where set.contains(byte) {
      let wordIndex = index / 64
      let bitIndex = index % 64
      words[wordIndex] |= UInt64(1) << UInt64(bitIndex)
    }
    self.words = words
  }
}

extension NormalizedRegex {
  fileprivate var primitiveByteSets: [ByteSet] {
    switch self {
    case .never, .epsilon:
      return []
    case .literal(let bytes):
      return bytes.map { ByteSet(bytes: [$0]) }
    case .byteClass(let set):
      return [set]
    case .concat(let children), .alt(let children):
      return children.flatMap(\.primitiveByteSets)
    case .repetition(let child, _, _):
      return child.primitiveByteSets
    }
  }
}
