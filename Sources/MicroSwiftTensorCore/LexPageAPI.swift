import MLX
import MicroSwiftLexerGen

public enum TensorLexer {
  public static func lexPage(
    bytes: [UInt8],
    validLen: Int32,
    baseOffset: Int64,
    artifact: ArtifactRuntime,
    options: LexOptions
  ) -> PageLexResult {
    precondition(validLen >= 0, "validLen must be non-negative")
    precondition(Int(validLen) <= bytes.count, "validLen must be <= bytes.count")

    let selectedBucket =
      PageBucket.bucket(for: Int32(bytes.count))
      ?? PageBucket(byteCapacity: Int32(max(bytes.count, 1)))
    let compiledPage = CompiledPageInput(
      bytes: bytes,
      validLen: validLen,
      baseOffset: baseOffset,
      bucket: selectedBucket,
      artifact: artifact
    )
    return lexPage(compiledPage: compiledPage, artifact: artifact, options: options)
  }

  public static func lexPage(
    compiledPage: CompiledPageInput,
    artifact: ArtifactRuntime,
    options: LexOptions
  ) -> PageLexResult {
    _ = compiledPage.baseOffset
    let boundedValidLen = max(0, min(Int(compiledPage.validLen), compiledPage.byteCapacity))
    guard boundedValidLen > 0 else {
      return PageLexResult(
        packedRows: [],
        rowCount: 0,
        errorSpans: [],
        overflowDiagnostic: nil
      )
    }

    let hostView = compiledPage.extractHostExecutionView(at: .transitionalFamilyExecution)

    // Phase A: Byte classification
    let classIDs = hostView.classIDs

    // Phase B: Per-rule candidate generation (using RuleBuckets)
    let candidateBatch = makeFastCandidateBatch(
      compiledPage: compiledPage,
      hostView: hostView,
      validLen: Int32(boundedValidLen),
      artifact: artifact
    )

    // Phase C: Device-resident winner reduction
    let winnerTensors = WinnerReduction.reduce(
      batch: candidateBatch,
      pageSize: hostView.bytes.count
    )
    var winners = WinnerReduction.hostWinners(from: winnerTensors, pageSize: hostView.bytes.count)

    if options.runtimeProfile == .v1Fallback, let fallback = artifact.fallback {
      let fallbackResult = FallbackKernelRunner(fallback: fallback).evaluatePage(
        classIDs: classIDs.map(UInt16.init),
        validLen: Int32(boundedValidLen)
      )
      winners = integrateWithFallback(
        fastWinners: winners,
        fallbackResult: fallbackResult,
        pageWidth: hostView.bytes.count
      )
    }

    // Phase D: Greedy non-overlap selection
    let selected = GreedySelector.select(winners: winners, validLen: Int32(boundedValidLen))

    // Phase E-G: Remap, coverage, emission via TransportEmitter
    return TransportEmitter.emit(
      selectedTokens: selected,
      bytes: hostView.bytes,
      validLen: Int32(boundedValidLen),
      remapTables: artifact.keywordRemaps,
      options: options,
      maxRowCapacity: Int32(boundedValidLen)
    )
  }

  private static func modeByte(_ mode: RuleMode) -> UInt8 {
    mode == .skip ? 1 : 0
  }

  fileprivate static func makeFastCandidateBatch(
    compiledPage: CompiledPageInput,
    hostView: HostPageExecutionView,
    validLen: Int32,
    artifact: ArtifactRuntime
  ) -> WinnerReduction.RuleTensorBatch {
    makeFastCandidateBatch(
      literalPage: compiledPage,
      bytes: hostView.bytes,
      classIDs: hostView.classIDs,
      validMask: hostView.validMask,
      validLen: validLen,
      artifact: artifact
    )
  }

  fileprivate static func makeFastCandidateBatch(
    bytes: [UInt8],
    classIDs: [UInt8],
    validMask: [Bool],
    validLen: Int32,
    artifact: ArtifactRuntime
  ) -> WinnerReduction.RuleTensorBatch {
    makeFastCandidateBatch(
      literalPage: nil,
      bytes: bytes,
      classIDs: classIDs,
      validMask: validMask,
      validLen: validLen,
      artifact: artifact
    )
  }

  private static func makeFastCandidateBatch(
    literalPage: CompiledPageInput?,
    bytes: [UInt8],
    classIDs: [UInt8],
    validMask: [Bool],
    validLen: Int32,
    artifact: ArtifactRuntime
  ) -> WinnerReduction.RuleTensorBatch {
    let buckets = RuleBuckets.build(from: artifact.rules)
    var lengthRows: [MLXArray] = []
    var priorityRows: [MLXArray] = []
    var ruleRows: [MLXArray] = []
    var tokenRows: [MLXArray] = []
    var modeRows: [MLXArray] = []

    let pageSize = bytes.count
    let reserveCount = artifact.rules.count
    lengthRows.reserveCapacity(reserveCount)
    priorityRows.reserveCapacity(reserveCount)
    ruleRows.reserveCapacity(reserveCount)
    tokenRows.reserveCapacity(reserveCount)
    modeRows.reserveCapacity(reserveCount)

    func appendCandidateRow(
      ruleID: UInt16,
      tokenKindID: UInt16,
      priorityRank: UInt16,
      mode: UInt8,
      candLenTensor: MLXArray
    ) {
      let normalizedCandLen = candLenTensor.asType(.uint16)
      precondition(
        Int(normalizedCandLen.shape[0]) == pageSize,
        "candidate tensor width must equal page size"
      )

      lengthRows.append(normalizedCandLen)
      priorityRows.append(mlxUInt16Filled(value: priorityRank, count: pageSize))
      ruleRows.append(mlxUInt16Filled(value: ruleID, count: pageSize))
      tokenRows.append(mlxUInt16Filled(value: tokenKindID, count: pageSize))
      modeRows.append(mlxUInt8Filled(value: mode, count: pageSize))
    }

    func appendCandidateRow(
      ruleID: UInt16,
      tokenKindID: UInt16,
      priorityRank: UInt16,
      mode: UInt8,
      candLenHost: [UInt16]
    ) {
      precondition(candLenHost.count == pageSize, "candidate host width must equal page size")
      appendCandidateRow(
        ruleID: ruleID,
        tokenKindID: tokenKindID,
        priorityRank: priorityRank,
        mode: mode,
        candLenTensor: mlxUInt16Tensor(candLenHost)
      )
    }

    for literalLength in buckets.literalBuckets.keys.sorted() {
      guard let rules = buckets.literalBuckets[literalLength] else { continue }
      for rule in rules {
        guard case .literal(let literalBytes) = rule.plan else { continue }
        if let literalPage {
          appendCandidateRow(
            ruleID: rule.ruleID,
            tokenKindID: rule.tokenKindID,
            priorityRank: rule.priorityRank,
            mode: modeByte(rule.mode),
            candLenTensor: LiteralExecution.evaluateLiteral(
              compiledPage: literalPage,
              literalBytes: literalBytes
            )
          )
        } else {
          appendCandidateRow(
            ruleID: rule.ruleID,
            tokenKindID: rule.tokenKindID,
            priorityRank: rule.priorityRank,
            mode: modeByte(rule.mode),
            candLenHost: LiteralExecution.evaluateLiteral(
              bytes: bytes,
              validMask: validMask,
              literalBytes: literalBytes
            )
          )
        }
      }
    }

    for rule in buckets.classRunRules {
      guard case .runClassRun(let bodyClassSetID, let minLength) = rule.plan else { continue }
      let candLen = ClassRunExecution.evaluateClassRun(
        classIDs: classIDs,
        validMask: validMask,
        bodyClassSetID: bodyClassSetID,
        minLength: minLength,
        classSetRuntime: artifact.classSetRuntime
      )
      appendCandidateRow(
        ruleID: rule.ruleID,
        tokenKindID: rule.tokenKindID,
        priorityRank: rule.priorityRank,
        mode: modeByte(rule.mode),
        candLenHost: candLen
      )
    }

    for rule in buckets.headTailRules {
      guard case .runHeadTail(let headClassSetID, let tailClassSetID) = rule.plan else { continue }
      let candLen = HeadTailExecution.evaluateHeadTail(
        classIDs: classIDs,
        validMask: validMask,
        headClassSetID: headClassSetID,
        tailClassSetID: tailClassSetID,
        classSetRuntime: artifact.classSetRuntime
      )
      appendCandidateRow(
        ruleID: rule.ruleID,
        tokenKindID: rule.tokenKindID,
        priorityRank: rule.priorityRank,
        mode: modeByte(rule.mode),
        candLenHost: candLen
      )
    }

    var nextStopBySetID: [UInt16: [Int32]] = [:]
    for rule in buckets.prefixedRules {
      guard case .runPrefixed(let prefix, let bodyClassSetID, let stopClassSetID) = rule.plan else {
        continue
      }

      let nextStop: [Int32]?
      if let stopClassSetID {
        if let cached = nextStopBySetID[stopClassSetID] {
          nextStop = cached
        } else {
          let stopMembership = MembershipKernels.membershipMask(
            classIDs: classIDs,
            setID: stopClassSetID,
            classSetRuntime: artifact.classSetRuntime
          )
          let stopMask = zip(stopMembership, validMask).map { membership, valid in
            membership && valid
          }
          let computed = NextStopHelper.computeNextStop(
            stopMask: stopMask,
            validLen: validLen
          )
          nextStopBySetID[stopClassSetID] = computed
          nextStop = computed
        }
      } else {
        nextStop = nil
      }

      let candLen = PrefixedExecution.evaluatePrefixed(
        bytes: bytes,
        classIDs: classIDs,
        validMask: validMask,
        prefix: prefix,
        bodyClassSetID: bodyClassSetID,
        stopClassSetID: stopClassSetID,
        classSetRuntime: artifact.classSetRuntime,
        nextStop: nextStop
      )
      appendCandidateRow(
        ruleID: rule.ruleID,
        tokenKindID: rule.tokenKindID,
        priorityRank: rule.priorityRank,
        mode: modeByte(rule.mode),
        candLenHost: candLen
      )
    }

    return WinnerReduction.RuleTensorBatch(
      candLenByRule: mlxStackRows(lengthRows, pageSize: pageSize, dtype: .uint16),
      priorityRankByRule: mlxStackRows(priorityRows, pageSize: pageSize, dtype: .uint16),
      ruleIDByRule: mlxStackRows(ruleRows, pageSize: pageSize, dtype: .uint16),
      tokenKindIDByRule: mlxStackRows(tokenRows, pageSize: pageSize, dtype: .uint16),
      modeByRule: mlxStackRows(modeRows, pageSize: pageSize, dtype: .uint8)
    )
  }
}

func executeFastFamilies(
  bytes: [UInt8],
  classIDs: [UInt16],
  validLen: Int,
  artifact: ArtifactRuntime
) -> [CandidateWinner] {
  _ = classIDs
  let boundedValidLen = max(0, min(validLen, bytes.count))
  let narrowedClassIDs = ByteClassifier.classify(
    bytes: bytes,
    byteToClassLUT: artifact.hostByteToClassLUT()
  )
  let validMask = ByteClassifier.validityMask(
    pageSize: bytes.count, validLen: Int32(boundedValidLen))
  let winners = WinnerReduction.hostWinners(
    from: WinnerReduction.reduce(
      batch: TensorLexer.makeFastCandidateBatch(
        bytes: bytes,
        classIDs: narrowedClassIDs,
        validMask: validMask,
        validLen: Int32(boundedValidLen),
        artifact: artifact
      ),
      pageSize: bytes.count
    ),
    pageSize: bytes.count
  )

  return winners.enumerated().map { position, winner in
    candidateWinner(from: winner, position: position)
  }
}

private func mlxUInt16Tensor(_ values: [UInt16]) -> MLXArray {
  withMLXCPU { MLXArray(values, [values.count]).asType(.uint16) }
}

private func mlxUInt16Filled(value: UInt16, count: Int) -> MLXArray {
  withMLXCPU { MLXArray(Array(repeating: value, count: count), [count]).asType(.uint16) }
}

private func mlxUInt8Filled(value: UInt8, count: Int) -> MLXArray {
  withMLXCPU { MLXArray(Array(repeating: value, count: count), [count]).asType(.uint8) }
}

private func mlxStackRows(_ rows: [MLXArray], pageSize: Int, dtype: DType) -> MLXArray {
  withMLXCPU {
    guard !rows.isEmpty else { return zeros([0, pageSize], dtype: dtype) }
    return stacked(rows.map { $0.asType(dtype) }, axis: 0)
  }
}
