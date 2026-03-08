import Foundation
import MLX
import MicroSwiftLexerGen

public struct DeviceLexResult: @unchecked Sendable {
  public let selectedTokenTensors: GreedySelector.SelectedTokenTensors
  public let byteTensor: MLXArray
  public let validLen: Int32
  public let maxRowCapacity: Int32
  public let rowCountTensor: MLXArray

  public init(
    selectedTokenTensors: GreedySelector.SelectedTokenTensors,
    byteTensor: MLXArray,
    validLen: Int32,
    maxRowCapacity: Int32,
    rowCountTensor: MLXArray
  ) {
    self.selectedTokenTensors = selectedTokenTensors
    self.byteTensor = byteTensor.asType(.uint8)
    self.validLen = validLen
    self.maxRowCapacity = maxRowCapacity
    self.rowCountTensor = rowCountTensor.asType(.int32)
  }

  public func hostRowCount() -> Int32 {
    rowCountTensor.asType(.int32).asArray(Int32.self).first ?? 0
  }
}

public enum TensorLexer {
  private static let fastPathCacheEventPrefix = "fast-path-graph-cache"
  private static let fastPathDefaultDeviceID = "mlx-cpu"
  private static let fastPathCacheLogSink = KernelCacheLogSink()
  private static let fastPathKernelCache = KernelCache(
    eventPrefix: fastPathCacheEventPrefix,
    logSink: fastPathCacheLogSink.record
  )

  public static func resetFastPathGraphCache() {
    fastPathKernelCache.clear()
    fastPathCacheLogSink.clear()
  }

  public static func fastPathGraphMetrics() -> FastPathGraphMetrics {
    let events = fastPathCacheLogSink.decodedRecords()
    let compileCount = events.filter { $0.event == "\(fastPathCacheEventPrefix)-store" }.count
    let cacheHits = events.filter { $0.event == "\(fastPathCacheEventPrefix)-hit" }.count
    let cacheMisses = events.filter { $0.event == "\(fastPathCacheEventPrefix)-miss" }.count
    return FastPathGraphMetrics(
      compileCount: compileCount,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      cacheEvents: events
    )
  }

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
    let deviceResult = lexPageDevice(
      compiledPage: compiledPage,
      artifact: artifact,
      options: options
    )
    return materialize(
      deviceResult: deviceResult,
      remapTables: [],
      options: options
    )
  }

  public static func lexPageDevice(
    compiledPage: CompiledPageInput,
    artifact: ArtifactRuntime,
    options: LexOptions
  ) -> DeviceLexResult {
    _ = compiledPage.baseOffset
    let boundedValidLen = max(0, min(Int(compiledPage.validLen), compiledPage.byteCapacity))
    guard boundedValidLen > 0 else {
      return DeviceLexResult(
        selectedTokenTensors: GreedySelector.SelectedTokenTensors(
          startPos: zeros([compiledPage.byteCapacity], dtype: .int32),
          length: zeros([compiledPage.byteCapacity], dtype: .uint16),
          ruleID: zeros([compiledPage.byteCapacity], dtype: .uint16),
          tokenKindID: zeros([compiledPage.byteCapacity], dtype: .uint16),
          mode: zeros([compiledPage.byteCapacity], dtype: .uint8),
          selectedMask: zeros([compiledPage.byteCapacity], dtype: .bool)
        ),
        byteTensor: compiledPage.byteTensor ?? zeros([compiledPage.byteCapacity], dtype: .uint8),
        validLen: 0,
        maxRowCapacity: 0,
        rowCountTensor: zeros([1], dtype: .int32)
      )
    }

    let pageSize = compiledPage.byteCapacity

    let cacheKey = makeFastPathCacheKey(
      compiledPage: compiledPage,
      artifact: artifact,
      options: options
    )
    let traceID = "fast-path-\(UUID().uuidString)"

    let cacheEntry: KernelCacheEntry
    do {
      cacheEntry = try fastPathKernelCache.getOrCreate(key: cacheKey, traceID: traceID) {
        try makeFastPathCacheEntry(
          pageSize: pageSize,
          artifact: artifact,
          options: options
        )
      }
    } catch {
      preconditionFailure("Fast-path graph cache resource creation failed: \(error)")
    }

    guard let fastPathGraph = cacheEntry.fastPathGraph else {
      preconditionFailure("KernelCacheEntry missing fastPathGraph for fast-path execution")
    }

    let byteTensor = compiledPage.byteTensor!
    let classIDTensor = compiledPage.classIDTensor!
    let validMaskTensor = compiledPage.validRangeMask(dtype: .bool)

    // Compiled candidate generation + winner reduction + greedy selection.
    let selectedTensors = fastPathGraph.execute(
      byteTensor: byteTensor,
      classIDTensor: classIDTensor,
      validMaskTensor: validMaskTensor
    )
    let keepMask =
      options.emitSkipTokens
      ? selectedTensors.selectedMask
      : selectedTensors.selectedMask .&& (selectedTensors.mode .!= UInt8(1))
    let rowCountTensor = sum(keepMask.asType(.int32)).asType(.int32)

    return DeviceLexResult(
      selectedTokenTensors: selectedTensors,
      byteTensor: byteTensor,
      validLen: Int32(boundedValidLen),
      maxRowCapacity: Int32(boundedValidLen),
      rowCountTensor: rowCountTensor
    )
  }

  public static func materialize(
    deviceResult: DeviceLexResult,
    remapTables: [KeywordRemapTable],
    options: LexOptions
  ) -> PageLexResult {
    TransportEmitter.emit(
      selectedTokenTensors: deviceResult.selectedTokenTensors,
      byteTensor: deviceResult.byteTensor,
      validLen: deviceResult.validLen,
      remapTables: remapTables,
      options: options,
      maxRowCapacity: deviceResult.maxRowCapacity
    )
  }

  private static func makeFastPathCacheKey(
    compiledPage: CompiledPageInput,
    artifact: ArtifactRuntime,
    options: LexOptions
  ) -> KernelCacheKey {
    KernelCacheKey(
      deviceID: fastPathDefaultDeviceID,
      artifactHash: artifact.artifactHash,
      pageBucket: compiledPage.byteCapacity,
      inputDType:
        "\(compiledPage.byteTensorDType)-\(compiledPage.classIDTensorDType)-\(compiledPage.validMaskTensorDType)",
      runtimeProfile: options.runtimeProfile.rawValue,
      layoutSignature: "fast-path-candidate-batch-v1"
    )
  }

  private static func makeFastPathCacheEntry(
    pageSize: Int,
    artifact: ArtifactRuntime,
    options: LexOptions
  ) throws -> KernelCacheEntry {
    let classCount = Set(artifact.hostByteToClassLUT()).count
    let metadata = KernelCacheRuntimeMetadata(
      backend: "mlx",
      deviceID: fastPathDefaultDeviceID,
      pipelineFunction: "fastPathPageGraph",
      constantTableByteCount: 0,
      fallbackRuleCount: 0,
      stepStride: Int(artifact.runtimeHints.maxBoundedRuleWidth),
      maxClassCount: classCount
    )

    return KernelCacheEntry(
      fastPathGraph: FastPathCompiledGraph(pageSize: pageSize, artifact: artifact),
      runtimeMetadata: metadata,
      createdAt: Date()
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

    // Use MLX tensor path when compiled page tensors are available
    let useMLXCandidates = literalPage?.classIDTensor != nil

    // Precompute shared tensor resources for MLX path
    let classIDTensor: MLXArray?
    let validMaskTensor: MLXArray?
    let byteTensor: MLXArray?
    let nextInvalidTensor: MLXArray?
    if useMLXCandidates, let literalPage {
      classIDTensor = literalPage.classIDTensor
      validMaskTensor = literalPage.validRangeMask(dtype: .bool)
      byteTensor =
        literalPage.byteTensor
        ?? MLXArray(bytes, [pageSize]).asType(.uint8)
      let niIndices = MLXArray(Int32(0)..<Int32(pageSize), [pageSize])
      let niSentinelFill = broadcast(MLXArray(Int32(pageSize)), to: [pageSize])
      let niInvalidIndices = which(.!validMaskTensor!, niIndices, niSentinelFill)
      nextInvalidTensor = cummin(niInvalidIndices, axis: 0, reverse: true)
    } else {
      classIDTensor = nil
      validMaskTensor = nil
      byteTensor = nil
      nextInvalidTensor = nil
    }

    for rule in buckets.classRunRules {
      guard case .runClassRun(let bodyClassSetID, let minLength) = rule.plan else { continue }
      if let classIDTensor, let validMaskTensor {
        appendCandidateRow(
          ruleID: rule.ruleID,
          tokenKindID: rule.tokenKindID,
          priorityRank: rule.priorityRank,
          mode: modeByte(rule.mode),
          candLenTensor: ClassRunExecution.evaluateClassRunMLX(
            classIDTensor: classIDTensor,
            validMaskTensor: validMaskTensor,
            bodyClassSetID: bodyClassSetID,
            minLength: minLength,
            classSetRuntime: artifact.classSetRuntime
          )
        )
      } else {
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
    }

    for rule in buckets.headTailRules {
      guard case .runHeadTail(let headClassSetID, let tailClassSetID) = rule.plan else { continue }
      if let classIDTensor, let validMaskTensor {
        appendCandidateRow(
          ruleID: rule.ruleID,
          tokenKindID: rule.tokenKindID,
          priorityRank: rule.priorityRank,
          mode: modeByte(rule.mode),
          candLenTensor: HeadTailExecution.evaluateHeadTailMLX(
            classIDTensor: classIDTensor,
            validMaskTensor: validMaskTensor,
            headClassSetID: headClassSetID,
            tailClassSetID: tailClassSetID,
            classSetRuntime: artifact.classSetRuntime
          )
        )
      } else {
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
    }

    var nextStopBySetID: [UInt16: [Int32]] = [:]
    var nextStopTensorBySetID: [UInt16: MLXArray] = [:]
    for rule in buckets.prefixedRules {
      guard case .runPrefixed(let prefix, let bodyClassSetID, let stopClassSetID) = rule.plan else {
        continue
      }

      if let classIDTensor, let validMaskTensor, let byteTensor, let nextInvalidTensor {
        // MLX tensor path
        let nextStopTensor: MLXArray?
        if let stopClassSetID {
          if let cached = nextStopTensorBySetID[stopClassSetID] {
            nextStopTensor = cached
          } else {
            let nsIndices = MLXArray(Int32(0)..<Int32(pageSize), [pageSize])
            let nsSentinelFill = broadcast(MLXArray(Int32(pageSize)), to: [pageSize])
            let stopMember = MembershipKernels.membershipMaskTensor(
              classIDTensor: classIDTensor,
              setID: stopClassSetID,
              classSetRuntime: artifact.classSetRuntime
            )
            let isStop = stopMember .&& validMaskTensor
            let stopIndices = which(isStop, nsIndices, nsSentinelFill)
            let computed = cummin(stopIndices, axis: 0, reverse: true)
            nextStopTensorBySetID[stopClassSetID] = computed
            nextStopTensor = computed
          }
        } else {
          nextStopTensor = nil
        }

        appendCandidateRow(
          ruleID: rule.ruleID,
          tokenKindID: rule.tokenKindID,
          priorityRank: rule.priorityRank,
          mode: modeByte(rule.mode),
          candLenTensor: PrefixedExecution.evaluatePrefixedMLX(
            byteTensor: byteTensor,
            classIDTensor: classIDTensor,
            validMaskTensor: validMaskTensor,
            prefix: prefix,
            bodyClassSetID: bodyClassSetID,
            classSetRuntime: artifact.classSetRuntime,
            nextInvalidTensor: nextInvalidTensor,
            nextStopTensor: nextStopTensor
          )
        )
      } else {
        // Host path
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
  MLXArray(values, [values.count]).asType(.uint16)
}

private func mlxUInt16Filled(value: UInt16, count: Int) -> MLXArray {
  broadcast(MLXArray(value).asType(.uint16), to: [count])
}

private func mlxUInt8Filled(value: UInt8, count: Int) -> MLXArray {
  broadcast(MLXArray(value).asType(.uint8), to: [count])
}

private func mlxStackRows(_ rows: [MLXArray], pageSize: Int, dtype: DType) -> MLXArray {
  guard !rows.isEmpty else { return zeros([0, pageSize], dtype: dtype) }
  return stacked(rows.map { $0.asType(dtype) }, axis: 0)
}
