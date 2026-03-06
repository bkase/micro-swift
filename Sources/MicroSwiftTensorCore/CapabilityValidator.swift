import MicroSwiftLexerGen

public enum RuntimeProfile: String, Sendable, Equatable {
  case v0 = "v0"
  case v1Fallback = "v1-fallback"
}

public enum CapabilityRejectionReason: String, Sendable, Equatable {
  case stateCapExceeded = "state-cap-exceeded"
  case missingTable = "missing-table"
  case widthExceeded = "width-exceeded"
  case maxLookaheadMismatch = "max-lookahead-mismatch"
  case localWindowPresent = "localWindow-present"
}

public struct CapabilityDiagnostic: Sendable, Equatable, CustomStringConvertible {
  public let ruleID: UInt16
  public let ruleName: String
  public let family: RuleFamily
  public let reason: CapabilityRejectionReason

  public init(
    ruleID: UInt16,
    ruleName: String,
    family: RuleFamily,
    reason: CapabilityRejectionReason
  ) {
    self.ruleID = ruleID
    self.ruleName = ruleName
    self.family = family
    self.reason = reason
  }

  public var description: String {
    "artifact-capability-error: unsupported \(family.rawValue) " +
      "ruleID=\(ruleID) name=\(ruleName) reason=\(reason.rawValue)"
  }

  public func formattedMessage(profile: RuntimeProfile) -> String {
    "artifact-capability-error: unsupported \(family.rawValue) for runtime profile \(profile.rawValue) " +
      "ruleID=\(ruleID) name=\(ruleName) reason=\(reason.rawValue)"
  }
}

public enum CapabilityValidator {
  private static let maxFallbackStates: UInt32 = 128

  public static func validate(
    artifact: LexerArtifact,
    profile: RuntimeProfile
  ) -> [CapabilityDiagnostic] {
    var diagnostics: [CapabilityDiagnostic] = []
    var combinedFallbackStates: UInt32 = 0
    let knownTokenKinds = Set(artifact.tokenKinds.map(\.tokenKindID))

    for rule in artifact.rules {
      switch profile {
      case .v0:
        validateV0Rule(
          rule: rule,
          knownTokenKinds: knownTokenKinds,
          diagnostics: &diagnostics
        )
      case .v1Fallback:
        validateV1FallbackRule(
          rule: rule,
          knownTokenKinds: knownTokenKinds,
          lookaheadLimit: artifact.runtimeHints.maxDeterministicLookaheadBytes,
          combinedFallbackStates: &combinedFallbackStates,
          diagnostics: &diagnostics
        )
      }
    }

    return diagnostics
  }

  private static func validateV0Rule(
    rule: LoweredRule,
    knownTokenKinds: Set<UInt16>,
    diagnostics: inout [CapabilityDiagnostic]
  ) {
    if !hasCompleteMetadata(rule: rule, knownTokenKinds: knownTokenKinds) {
      diagnostics.append(diagnostic(for: rule, reason: .missingTable))
    }

    switch rule.family {
    case .literal, .run:
      return
    case .localWindow:
      diagnostics.append(diagnostic(for: rule, reason: .localWindowPresent))
    case .fallback:
      diagnostics.append(diagnostic(for: rule, reason: .missingTable))
    }
  }

  private static func validateV1FallbackRule(
    rule: LoweredRule,
    knownTokenKinds: Set<UInt16>,
    lookaheadLimit: UInt16,
    combinedFallbackStates: inout UInt32,
    diagnostics: inout [CapabilityDiagnostic]
  ) {
    if !hasCompleteMetadata(rule: rule, knownTokenKinds: knownTokenKinds) {
      diagnostics.append(diagnostic(for: rule, reason: .missingTable))
    }

    switch rule.family {
    case .literal, .run:
      return
    case .localWindow:
      diagnostics.append(diagnostic(for: rule, reason: .localWindowPresent))
    case .fallback:
      guard case .fallback(
        let stateCount,
        let classCount,
        let transitionRowStride,
        let startState,
        let acceptingStates,
        let transitions
      ) = rule.plan else {
        diagnostics.append(diagnostic(for: rule, reason: .missingTable))
        return
      }

      if !isValidFallbackPayload(
        stateCount: stateCount,
        classCount: classCount,
        transitionRowStride: transitionRowStride,
        startState: startState,
        acceptingStates: acceptingStates,
        transitions: transitions
      ) {
        diagnostics.append(diagnostic(for: rule, reason: .missingTable))
      }

      let maxWidth = rule.maxWidth ?? 0
      if maxWidth == 0 || maxWidth < rule.minWidth {
        diagnostics.append(diagnostic(for: rule, reason: .widthExceeded))
      }
      if maxWidth > lookaheadLimit {
        diagnostics.append(diagnostic(for: rule, reason: .maxLookaheadMismatch))
      }

      let (nextCombined, didOverflow) = combinedFallbackStates.addingReportingOverflow(stateCount)
      combinedFallbackStates = nextCombined
      if didOverflow || combinedFallbackStates > maxFallbackStates {
        diagnostics.append(diagnostic(for: rule, reason: .stateCapExceeded))
      }
    }
  }

  private static func hasCompleteMetadata(
    rule: LoweredRule,
    knownTokenKinds: Set<UInt16>
  ) -> Bool {
    !rule.name.isEmpty && knownTokenKinds.contains(rule.tokenKindID)
  }

  private static func isValidFallbackPayload(
    stateCount: UInt32,
    classCount: UInt16,
    transitionRowStride: UInt16,
    startState: UInt32,
    acceptingStates: [UInt32],
    transitions: [UInt32]
  ) -> Bool {
    guard stateCount > 0, classCount > 0, transitionRowStride == classCount else {
      return false
    }
    guard startState < stateCount else {
      return false
    }
    guard acceptingStates.allSatisfy({ $0 < stateCount }) else {
      return false
    }

    let expectedEntries = Int(stateCount) * Int(transitionRowStride)
    guard transitions.count == expectedEntries else {
      return false
    }

    return transitions.allSatisfy { $0 < stateCount }
  }

  private static func diagnostic(
    for rule: LoweredRule,
    reason: CapabilityRejectionReason
  ) -> CapabilityDiagnostic {
    CapabilityDiagnostic(
      ruleID: rule.ruleID,
      ruleName: rule.name,
      family: rule.family,
      reason: reason
    )
  }
}
