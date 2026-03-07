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

  static func backendNameForTesting() -> String {
    RunFamilyMetalExecutorProvider.shared.backendName
  }
}
