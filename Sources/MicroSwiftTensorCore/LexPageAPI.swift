import MicroSwiftLexerGen

/// The pure tensor-core entry point. Implemented in later beads.
public enum TensorLexer {
  public static func lexPage(
    bytes: [UInt8],
    validLen: Int32,
    baseOffset: Int64,
    artifact: ArtifactRuntime,
    options: LexOptions
  ) -> PageLexResult {
    _ = baseOffset
    precondition(validLen >= 0, "validLen must be non-negative")
    precondition(Int(validLen) <= bytes.count, "validLen must be <= bytes.count")

    // Phase A: Byte classification
    let classIDs = ByteClassifier.classify(bytes: bytes, byteToClassLUT: artifact.byteToClassLUT)
    let validMask = ByteClassifier.validityMask(pageSize: bytes.count, validLen: validLen)

    // Phase B: Per-rule candidate generation (using RuleBuckets)
    let buckets = RuleBuckets.build(from: artifact.rules)
    var candidates: [WinnerReduction.RuleCandidate] = []
    candidates.reserveCapacity(artifact.rules.count)

    for literalLength in buckets.literalBuckets.keys.sorted() {
      guard let rules = buckets.literalBuckets[literalLength] else { continue }
      for rule in rules {
        guard case .literal(let literalBytes) = rule.plan else { continue }
        let candLen = LiteralExecution.evaluateLiteral(
          bytes: bytes,
          validMask: validMask,
          literalBytes: literalBytes
        )
        candidates.append(
          WinnerReduction.RuleCandidate(
            ruleID: rule.ruleID,
            tokenKindID: rule.tokenKindID,
            priorityRank: rule.priorityRank,
            mode: modeByte(rule.mode),
            candLen: candLen
          )
        )
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
      candidates.append(
        WinnerReduction.RuleCandidate(
          ruleID: rule.ruleID,
          tokenKindID: rule.tokenKindID,
          priorityRank: rule.priorityRank,
          mode: modeByte(rule.mode),
          candLen: candLen
        )
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
      candidates.append(
        WinnerReduction.RuleCandidate(
          ruleID: rule.ruleID,
          tokenKindID: rule.tokenKindID,
          priorityRank: rule.priorityRank,
          mode: modeByte(rule.mode),
          candLen: candLen
        )
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
      candidates.append(
        WinnerReduction.RuleCandidate(
          ruleID: rule.ruleID,
          tokenKindID: rule.tokenKindID,
          priorityRank: rule.priorityRank,
          mode: modeByte(rule.mode),
          candLen: candLen
        )
      )
    }

    // Phase C: Hierarchical winner reduction
    let winners = WinnerReduction.reduce(candidates: candidates, pageSize: bytes.count)

    // Phase D: Greedy non-overlap selection
    let selected = GreedySelector.select(winners: winners, validLen: validLen)

    // Phase E-G: Remap, coverage, emission via TransportEmitter
    return TransportEmitter.emit(
      selectedTokens: selected,
      bytes: bytes,
      validLen: validLen,
      remapTables: artifact.keywordRemaps,
      options: options,
      maxRowCapacity: validLen
    )
  }

  private static func modeByte(_ mode: RuleMode) -> UInt8 {
    mode == .skip ? 1 : 0
  }
}
