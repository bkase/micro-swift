import MLX

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
    do {
      return try RunFamilyMetalExecutorProvider.shared.evaluateClassRun(
        classIDs: classIDs,
        validMask: validMask,
        bodyClassSetID: bodyClassSetID,
        minLength: minLength,
        classSetRuntime: classSetRuntime
      )
    } catch {
      preconditionFailure("classRun Metal execution failed: \(error)")
    }
  }

  /// Pure MLX tensor evaluation of a classRun rule. No host arrays produced.
  /// Returns candLen[P] as MLXArray (uint16).
  public static func evaluateClassRunMLX(
    classIDTensor: MLXArray,
    validMaskTensor: MLXArray,
    bodyClassSetID: UInt16,
    minLength: UInt16,
    classSetRuntime: ClassSetRuntime
  ) -> MLXArray {
    withMLXCPU {
      let pageLen = Int(classIDTensor.shape[0])
      guard pageLen > 0 else { return zeros([0], dtype: .uint16) }

      let indices = MLXArray(Int32(0)..<Int32(pageLen), [pageLen])

      // 1. Membership gather: inBody = classSetContains(bodyClassSetID, classID) && valid
      let memberMask = MembershipKernels.membershipMaskTensor(
        classIDTensor: classIDTensor,
        setID: bodyClassSetID,
        classSetRuntime: classSetRuntime
      )
      let inBody = memberMask .&& validMaskTensor

      // 2. isStart = inBody && !prev_inBody (edge detection)
      let prevInBody = concatenated(
        [MLXArray([false], [1]), inBody[0..<(pageLen - 1)]],
        axis: 0
      )
      let isStart = inBody .&& .!prevInBody

      // 3. isEnd = inBody && !next_inBody
      let nextInBody = concatenated(
        [inBody[1..<pageLen], MLXArray([false], [1])],
        axis: 0
      )
      let isEnd = inBody .&& .!nextInBody

      // 4. endPos = where isEnd, index, sentinel pageLen
      let sentinelFill = MLXArray(Array(repeating: Int32(pageLen), count: pageLen), [pageLen])
      let endPos = which(isEnd, indices, sentinelFill)

      // 5. propagatedEnds = cummin(endPos, reverse=true) → nearest end for each position
      let propagatedEnds = cummin(endPos, axis: 0, reverse: true)

      // 6. lengths = propagatedEnds - indices + 1
      let lengths = (propagatedEnds - indices + MLXArray(Int32(1))).asType(.uint16)

      // 7. candLen = where isStart, lengths, 0
      let candLen = which(isStart, lengths, zeros([pageLen], dtype: .uint16))

      // 8. Apply minLength filter
      if minLength <= 1 {
        return candLen
      }
      let minLenTensor = MLXArray(minLength)
      return which(candLen .>= minLenTensor, candLen, zeros([pageLen], dtype: .uint16))
    }
  }

  public static func backendNameForTesting() -> String {
    RunFamilyMetalExecutorProvider.shared.backendName
  }

  public static func resetDispatchMetrics() {
    RunFamilyMetalExecutorProvider.resetDispatchMetrics()
  }

  public static func dispatchMetrics() -> RunFamilyDispatchMetrics {
    RunFamilyMetalExecutorProvider.dispatchMetrics()
  }
}
