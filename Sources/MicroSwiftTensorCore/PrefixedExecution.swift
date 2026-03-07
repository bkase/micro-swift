import MLX

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

  /// Pure MLX tensor evaluation of a prefixed rule. No host arrays produced.
  /// nextInvalidTensor: precomputed [P] int32, index of nearest invalid position (cummin form).
  /// nextStopTensor: precomputed [P] int32, index of nearest stop position (cummin form), or nil.
  /// Returns candLen[P] as MLXArray (uint16).
  public static func evaluatePrefixedMLX(
    byteTensor: MLXArray,
    classIDTensor: MLXArray,
    validMaskTensor: MLXArray,
    prefix: [UInt8],
    bodyClassSetID: UInt16,
    classSetRuntime: ClassSetRuntime,
    nextInvalidTensor: MLXArray,
    nextStopTensor: MLXArray?
  ) -> MLXArray {
    withMLXCPU {
      let pageLen = Int(byteTensor.shape[0])
      guard pageLen > 0 else { return zeros([0], dtype: .uint16) }

      let prefixLen = prefix.count
      guard prefixLen < pageLen else { return zeros([pageLen], dtype: .uint16) }

      let indices = MLXArray(Int32(0)..<Int32(pageLen), [pageLen])
      let sentinel = Int32(pageLen)
      let sentinelFill = broadcast(MLXArray(sentinel), to: [pageLen])

      // 1. Prefix start mask: shifted byte comparisons
      let prefixStartMask: MLXArray = {
        var mask = validMaskTensor
        for (offset, expectedByte) in prefix.enumerated() {
          let shiftedBytes: MLXArray
          let shiftedValid: MLXArray
          if offset == 0 {
            shiftedBytes = byteTensor
            shiftedValid = validMaskTensor
          } else {
            shiftedBytes = concatenated(
              [
                byteTensor[offset..<pageLen],
                zeros([offset], dtype: byteTensor.dtype),
              ],
              axis: 0
            )
            shiftedValid = concatenated(
              [
                validMaskTensor[offset..<pageLen],
                MLXArray(Array(repeating: false, count: offset), [offset]),
              ],
              axis: 0
            )
          }
          let byteMatch = shiftedBytes .== MLXArray(expectedByte)
          let updated = mask .&& shiftedValid .&& byteMatch
          mask = updated
        }

        // Zero out positions where prefix can't fit
        if prefixLen > 0 {
          let lastValidStart = pageLen - prefixLen
          if lastValidStart + 1 < pageLen {
            let tailMask = indices .<= MLXArray(Int32(lastValidStart))
            let filtered = mask .&& tailMask
            mask = filtered
          }
        }
        return mask
      }()

      // 2. Body boundary: nextBodyBreak via cummin
      let bodyMember = MembershipKernels.membershipMaskTensor(
        classIDTensor: classIDTensor,
        setID: bodyClassSetID,
        classSetRuntime: classSetRuntime
      )
      let inBody = bodyMember .&& validMaskTensor
      let bodyBreakIndices = which(.!inBody, indices, sentinelFill)
      let nextBodyBreak = cummin(bodyBreakIndices, axis: 0, reverse: true)

      // 3. Shift boundaries by prefixLen (look up at bodyStart = start + prefixLen)
      let shiftedNextBodyBreak = concatenated(
        [
          nextBodyBreak[prefixLen..<pageLen],
          broadcast(MLXArray(sentinel), to: [prefixLen]),
        ],
        axis: 0
      )
      let shiftedNextInvalid = concatenated(
        [
          nextInvalidTensor[prefixLen..<pageLen],
          broadcast(MLXArray(sentinel), to: [prefixLen]),
        ],
        axis: 0
      )

      // 4. Compute cursor = min of all boundaries
      let cursor: MLXArray = {
        let base = minimum(shiftedNextBodyBreak, shiftedNextInvalid)
        guard let nextStopTensor else { return base }
        let shiftedNextStop = concatenated(
          [
            nextStopTensor[prefixLen..<pageLen],
            broadcast(MLXArray(sentinel), to: [prefixLen]),
          ],
          axis: 0
        )
        return minimum(base, shiftedNextStop)
      }()

      // 5. totalLen = cursor - indices (since prefixLen + (cursor - (indices + prefixLen)) = cursor - indices)
      let totalLen = (cursor - indices).asType(.uint16)

      // 6. Mask by prefix start positions
      return which(prefixStartMask, totalLen, zeros([pageLen], dtype: .uint16))
    }
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
