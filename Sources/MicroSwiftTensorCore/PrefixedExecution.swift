public enum PrefixedExecution {
  /// Evaluate a prefixed rule (e.g. line comments: prefix="//", body=notNewline, stop=newline).
  /// 1. Find prefix matches
  /// 2. Extend through body bytes until stop ClassSet member (or end of valid region)
  /// Returns candLen[P].
  public static func evaluatePrefixed(
    bytes: [UInt8],
    classIDs: [UInt8],
    validMask: [Bool],
    prefix: [UInt8],
    bodyClassSetID: UInt16,
    stopClassSetID: UInt16?,
    classSetRuntime: ClassSetRuntime,
    nextStop: [Int32]?
  ) -> [UInt16] {
    let count = min(bytes.count, classIDs.count, validMask.count)
    guard count > 0 else { return [] }

    let prefixLength = prefix.count
    let bodyMask = MembershipKernels.membershipMask(
      classIDs: Array(classIDs.prefix(count)),
      setID: bodyClassSetID,
      classSetRuntime: classSetRuntime
    )

    var nextInvalid = Array(repeating: count, count: count + 1)
    for index in stride(from: count - 1, through: 0, by: -1) {
      nextInvalid[index] = validMask[index] ? nextInvalid[index + 1] : index
    }

    var stopMask: [Bool] = []
    if let stopClassSetID {
      stopMask = MembershipKernels.membershipMask(
        classIDs: Array(classIDs.prefix(count)),
        setID: stopClassSetID,
        classSetRuntime: classSetRuntime
      )
    }

    var candidateLengths = Array(repeating: UInt16(0), count: count)

    for start in 0..<count {
      guard
        prefixMatches(
          bytes: bytes,
          validMask: validMask,
          prefix: prefix,
          start: start,
          count: count
        )
      else {
        continue
      }

      let bodyStart = start + prefixLength
      var bodyEnd = bodyStart < count ? nextInvalid[bodyStart] : bodyStart

      if let stopClassSetID {
        let stopIndex = findStopIndex(
          start: bodyStart,
          count: count,
          validMask: validMask,
          stopMask: stopMask,
          nextStop: nextStop,
          stopClassSetID: stopClassSetID,
          classSetRuntime: classSetRuntime,
          classIDs: classIDs
        )
        bodyEnd = min(bodyEnd, stopIndex)
      }

      var cursor = bodyStart
      while cursor < bodyEnd && bodyMask[cursor] {
        cursor += 1
      }

      let totalLength = min(prefixLength + (cursor - bodyStart), Int(UInt16.max))
      candidateLengths[start] = UInt16(totalLength)
    }

    return candidateLengths
  }

  private static func prefixMatches(
    bytes: [UInt8],
    validMask: [Bool],
    prefix: [UInt8],
    start: Int,
    count: Int
  ) -> Bool {
    if prefix.isEmpty { return start < count && validMask[start] }
    if start + prefix.count > count { return false }

    for offset in 0..<prefix.count {
      let position = start + offset
      if !validMask[position] || bytes[position] != prefix[offset] {
        return false
      }
    }

    return true
  }

  private static func findStopIndex(
    start: Int,
    count: Int,
    validMask: [Bool],
    stopMask: [Bool],
    nextStop: [Int32]?,
    stopClassSetID: UInt16,
    classSetRuntime: ClassSetRuntime,
    classIDs: [UInt8]
  ) -> Int {
    guard start < count else { return start }

    if let nextStop, start < nextStop.count {
      let stopFromHelper = Int(nextStop[start])
      if stopFromHelper >= start && stopFromHelper < count {
        return stopFromHelper
      }
      if stopFromHelper >= count {
        return count
      }
    }

    for index in start..<count {
      guard validMask[index] else { return index }
      if stopMask.isEmpty {
        if classSetRuntime.contains(setID: stopClassSetID, classID: classIDs[index]) {
          return index
        }
      } else if stopMask[index] {
        return index
      }
    }

    return count
  }
}
