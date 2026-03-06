public struct FallbackPageResult: Sendable, Equatable {
  public let fallbackLen: [UInt16]
  public let fallbackPriorityRank: [UInt16]
  public let fallbackRuleID: [UInt16]
  public let fallbackTokenKindID: [UInt16]
  public let fallbackMode: [UInt8]

  public init(
    fallbackLen: [UInt16],
    fallbackPriorityRank: [UInt16],
    fallbackRuleID: [UInt16],
    fallbackTokenKindID: [UInt16],
    fallbackMode: [UInt8]
  ) {
    self.fallbackLen = fallbackLen
    self.fallbackPriorityRank = fallbackPriorityRank
    self.fallbackRuleID = fallbackRuleID
    self.fallbackTokenKindID = fallbackTokenKindID
    self.fallbackMode = fallbackMode
  }
}

public struct FallbackKernelRunner: Sendable {
  public let fallback: FallbackRuntime
  let compiledKernel: FallbackMetalCompiledKernel?

  public init(fallback: FallbackRuntime) {
    self.fallback = fallback
    self.compiledKernel = nil
  }

  init(fallback: FallbackRuntime, compiledKernel: FallbackMetalCompiledKernel?) {
    self.fallback = fallback
    self.compiledKernel = compiledKernel
  }

  public func evaluatePage(classIDs: [UInt16], validLen: Int32) -> FallbackPageResult {
    runFallbackPage(
      classIDs: classIDs,
      validLen: validLen,
      fallback: fallback,
      compiledKernel: compiledKernel
    )
  }

  public func evaluatePage(
    classIDs: [UInt16],
    validLen: Int32,
    observability: inout FallbackObservability
  ) -> FallbackPageResult {
    withUnsafeMutablePointer(to: &observability) { observabilityPointer in
      runFallbackPage(
        classIDs: classIDs,
        validLen: validLen,
        fallback: fallback,
        compiledKernel: compiledKernel,
        observability: observabilityPointer
      )
    }
  }
}

public func evaluatePage(
  classIDs: [UInt16],
  validLen: Int32,
  fallback: FallbackRuntime
) -> FallbackPageResult {
  runFallbackPage(classIDs: classIDs, validLen: validLen, fallback: fallback)
}

private func runFallbackPage(
  classIDs: [UInt16],
  validLen: Int32,
  fallback: FallbackRuntime,
  compiledKernel: FallbackMetalCompiledKernel? = nil,
  observability: UnsafeMutablePointer<FallbackObservability>? = nil
) -> FallbackPageResult {
  let pageWidth = classIDs.count
  let boundedValidLen = max(0, min(Int(validLen), pageWidth))

  if let observability {
    for index in 0..<boundedValidLen {
      if startEligible(classID: classIDs[index], fallback: fallback) {
        observability.pointee.recordEntered()
      } else {
        observability.pointee.recordSkippedByStartMask()
      }
    }
  }

  do {
    let kernel: FallbackMetalCompiledKernel
    if let compiled = compiledKernel {
      kernel = compiled
    } else {
      kernel = try FallbackMetalExecutorProvider.shared.compileKernel(fallback: fallback)
    }

    let result = try FallbackMetalExecutorProvider.shared.evaluate(
      classIDs: classIDs,
      boundedValidLen: boundedValidLen,
      compiledKernel: kernel
    )
    observability?.pointee.recordKernelBackendDispatch()
    return result
  } catch {
    preconditionFailure("Fallback Metal executor failed: \(error)")
  }
}

private func startEligible(classID: UInt16, fallback: FallbackRuntime) -> Bool {
  if classID < 64 {
    let mask = UInt64(1) << UInt64(classID)
    return (fallback.startClassMaskLo & mask) != 0
  }
  if classID < 128 {
    let mask = UInt64(1) << UInt64(classID - 64)
    return (fallback.startClassMaskHi & mask) != 0
  }
  return false
}
