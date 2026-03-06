public enum ClassRunExecution {
  /// Evaluate a classRun rule.
  /// inBody = validMask && classSetContains(bodyClassSetID, classID)
  /// Find maximal runs of inBody, apply minLength filter.
  /// Returns candLen[P] with the run length at each start position (0 if not a start or below minLength).
  public static func evaluateClassRun(
    classIDs: [UInt8],
    validMask: [Bool],
    bodyClassSetID: UInt16,
    minLength: UInt16,
    classSetRuntime: ClassSetRuntime
  ) -> [UInt16] {
    let positionCount = min(classIDs.count, validMask.count)
    guard positionCount > 0 else { return [] }

    var inBody = Array(repeating: false, count: positionCount)
    for index in 0..<positionCount {
      inBody[index] =
        validMask[index]
        && classSetRuntime.contains(setID: bodyClassSetID, classID: classIDs[index])
    }

    var starts: [Int] = []
    var ends: [Int] = []
    starts.reserveCapacity(positionCount)
    ends.reserveCapacity(positionCount)

    for index in 0..<positionCount {
      if inBody[index] && (index == 0 || !inBody[index - 1]) {
        starts.append(index)
      }
      if inBody[index] && (index == positionCount - 1 || !inBody[index + 1]) {
        ends.append(index)
      }
    }

    var candidateLengths = Array(repeating: UInt16(0), count: positionCount)
    let runCount = min(starts.count, ends.count)

    for runIndex in 0..<runCount {
      let start = starts[runIndex]
      let end = ends[runIndex]
      let length = UInt16(end - start + 1)
      if length >= minLength {
        candidateLengths[start] = length
      }
    }

    return candidateLengths
  }
}
