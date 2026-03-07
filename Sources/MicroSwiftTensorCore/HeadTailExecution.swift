import MLX

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
    do {
      return try RunFamilyMetalExecutorProvider.shared.evaluateHeadTail(
        classIDs: classIDs,
        validMask: validMask,
        headClassSetID: headClassSetID,
        tailClassSetID: tailClassSetID,
        classSetRuntime: classSetRuntime
      )
    } catch {
      preconditionFailure("headTail Metal execution failed: \(error)")
    }
  }

  /// Pure MLX tensor evaluation of a headTail rule. No host arrays produced.
  /// Returns candLen[P] as MLXArray (uint16).
  public static func evaluateHeadTailMLX(
    classIDTensor: MLXArray,
    validMaskTensor: MLXArray,
    headClassSetID: UInt16,
    tailClassSetID: UInt16,
    classSetRuntime: ClassSetRuntime
  ) -> MLXArray {
    let pageLen = Int(classIDTensor.shape[0])
      guard pageLen > 0 else { return zeros([0], dtype: .uint16) }

      let indices = MLXArray(Int32(0)..<Int32(pageLen), [pageLen])

      // 1. isHead and isTail membership
      let isHead =
        MembershipKernels.membershipMaskTensor(
          classIDTensor: classIDTensor,
          setID: headClassSetID,
          classSetRuntime: classSetRuntime
        ) .&& validMaskTensor

      let isTail =
        MembershipKernels.membershipMaskTensor(
          classIDTensor: classIDTensor,
          setID: tailClassSetID,
          classSetRuntime: classSetRuntime
        ) .&& validMaskTensor

      // 2. isStart = isHead && !prevIsTail (maximal munch)
      let prevIsTail = concatenated(
        [MLXArray([false], [1]), isTail[0..<(pageLen - 1)]],
        axis: 0
      )
      let isStart = isHead .&& .!prevIsTail

      // 3. validChar = isHead || isTail (for end detection)
      let validChar = isHead .|| isTail

      // 4. isEnd = validChar && !nextIsTail
      let nextIsTail = concatenated(
        [isTail[1..<pageLen], MLXArray([false], [1])],
        axis: 0
      )
      let isEnd = validChar .&& .!nextIsTail

      // 5. endPos = where isEnd, index, sentinel pageLen
      let sentinelFill = broadcast(MLXArray(Int32(pageLen)), to: [pageLen])
      let endPos = which(isEnd, indices, sentinelFill)

      // 6. propagatedEnds = cummin(endPos, reverse=true)
      let propagatedEnds = cummin(endPos, axis: 0, reverse: true)

      // 7. lengths = propagatedEnds - indices + 1
      let lengths = (propagatedEnds - indices + MLXArray(Int32(1))).asType(.uint16)

      // 8. candLen = where isStart, lengths, 0
      return which(isStart, lengths, zeros([pageLen], dtype: .uint16))
  }

  static func backendNameForTesting() -> String {
    RunFamilyMetalExecutorProvider.shared.backendName
  }
}
