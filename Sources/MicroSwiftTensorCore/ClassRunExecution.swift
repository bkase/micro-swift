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
