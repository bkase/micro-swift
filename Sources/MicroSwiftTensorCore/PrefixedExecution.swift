public enum PrefixedExecution {
  /// Evaluate a prefixed rule (e.g. line comments: prefix="//", body=notNewline, stop=newline).
  /// Computes page-local masks and boundaries, then emits candLen[P].
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
    let truncatedClassIDs = Array(classIDs.prefix(count))

    let prefixStartMask = makePrefixStartMask(
      bytes: bytes,
      validMask: validMask,
      prefix: prefix,
      count: count
    )
    let bodyMask = MembershipKernels.membershipMask(
      classIDs: truncatedClassIDs,
      setID: bodyClassSetID,
      classSetRuntime: classSetRuntime
    )

    var nextInvalid = Array(repeating: count, count: count + 1)
    for index in stride(from: count - 1, through: 0, by: -1) {
      nextInvalid[index] = validMask[index] ? nextInvalid[index + 1] : index
    }

    let stopNextIndex: [Int]?
    if let stopClassSetID {
      let rawStopMask = MembershipKernels.membershipMask(
        classIDs: truncatedClassIDs,
        setID: stopClassSetID,
        classSetRuntime: classSetRuntime
      )
      let stopMask = zip(rawStopMask, validMask).map { isStop, valid in
        isStop && valid
      }
      let contiguousValidLen = Int32(nextInvalid[0])
      stopNextIndex = normalizedNextStop(
        provided: nextStop,
        stopMask: stopMask,
        count: count,
        validLen: contiguousValidLen
      )
    } else {
      stopNextIndex = nil
    }

    var nextBodyBreak = Array(repeating: count, count: count + 1)
    for index in stride(from: count - 1, through: 0, by: -1) {
      let inBody = validMask[index] && bodyMask[index]
      nextBodyBreak[index] = inBody ? nextBodyBreak[index + 1] : index
    }

    var candidateLengths = Array(repeating: UInt16(0), count: count)

    for start in 0..<count {
      guard prefixStartMask[start] else { continue }

      let bodyStart = start + prefixLength
      guard bodyStart <= count else { continue }

      var bodyEnd = bodyStart < count ? nextInvalid[bodyStart] : bodyStart
      if let stopNextIndex, bodyStart < count {
        bodyEnd = min(bodyEnd, stopNextIndex[bodyStart])
      }

      let firstBodyBreak = bodyStart < count ? nextBodyBreak[bodyStart] : bodyStart
      let cursor = min(firstBodyBreak, bodyEnd)
      let totalLength = min(prefixLength + (cursor - bodyStart), Int(UInt16.max))
      candidateLengths[start] = UInt16(totalLength)
    }

    return candidateLengths
  }

  private static func makePrefixStartMask(
    bytes: [UInt8],
    validMask: [Bool],
    prefix: [UInt8],
    count: Int
  ) -> [Bool] {
    guard count > 0 else { return [] }
    guard !prefix.isEmpty else { return Array(validMask.prefix(count)) }

    var startMask = Array(repeating: true, count: count)

    for (offset, expectedByte) in prefix.enumerated() {
      for start in 0..<count {
        let position = start + offset
        let matches =
          position < count
          && validMask[position]
          && bytes[position] == expectedByte
        startMask[start] = startMask[start] && matches
      }
    }

    if prefix.count <= count {
      let lastValidStart = count - prefix.count
      if lastValidStart + 1 < count {
        for start in (lastValidStart + 1)..<count {
          startMask[start] = false
        }
      }
    } else {
      for start in 0..<count {
        startMask[start] = false
      }
    }

    return startMask
  }

  private static func normalizedNextStop(
    provided: [Int32]?,
    stopMask: [Bool],
    count: Int,
    validLen: Int32
  ) -> [Int] {
    let source: [Int32]
    if let provided, provided.count >= count {
      source = provided
    } else {
      source = NextStopHelper.computeNextStop(stopMask: stopMask, validLen: validLen)
    }

    return (0..<count).map { index in
      guard index < source.count else { return count }
      let stop = Int(source[index])
      if stop < index {
        return index
      }
      return min(stop, count)
    }
  }
}
