public enum HeadTailExecution {
  /// Evaluate a headTail rule (e.g. identifiers: head=identStart, tail=identContinue).
  /// startMask[i] = isHead[i] && (i == 0 || !isTail[i-1])
  /// Then extend through maximal contiguous isTail segment.
  /// Returns candLen[P].
  public static func evaluateHeadTail(
    classIDs: [UInt8],
    validMask: [Bool],
    headClassSetID: UInt16,
    tailClassSetID: UInt16,
    classSetRuntime: ClassSetRuntime
  ) -> [UInt16] {
    let count = classIDs.count
    guard count > 0 else { return [] }

    var isHead = Array(repeating: false, count: count)
    var isTail = Array(repeating: false, count: count)

    for i in 0..<count {
      let isValid = i < validMask.count ? validMask[i] : false
      guard isValid else { continue }
      let classID = classIDs[i]
      isHead[i] = classSetRuntime.contains(setID: headClassSetID, classID: classID)
      isTail[i] = classSetRuntime.contains(setID: tailClassSetID, classID: classID)
    }

    var candLen = Array(repeating: UInt16(0), count: count)
    for start in 0..<count {
      let startsHere = isHead[start] && (start == 0 || !isTail[start - 1])
      guard startsHere else { continue }

      var end = start
      while end + 1 < count && isTail[end + 1] {
        end += 1
      }

      let length = end - start + 1
      candLen[start] = UInt16(clamping: length)
    }

    return candLen
  }
}
