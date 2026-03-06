import MicroSwiftLexerGen

public enum CapabilityValidator {
  public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let diagnostics: [CapabilityDiagnostic]

    public init(isValid: Bool, diagnostics: [CapabilityDiagnostic]) {
      self.isValid = isValid
      self.diagnostics = diagnostics
    }
  }

  public struct CapabilityDiagnostic: Sendable, Equatable {
    public let ruleID: UInt16
    public let ruleName: String
    public let family: String
    public let message: String

    public init(ruleID: UInt16, ruleName: String, family: String, message: String) {
      self.ruleID = ruleID
      self.ruleName = ruleName
      self.family = family
      self.message = message
    }
  }

  /// Validate that the artifact only contains families supported by runtime profile v0.
  /// Supported plans: literal, runClassRun, runHeadTail, runPrefixed.
  public static func validate(_ artifact: ArtifactRuntime) -> ValidationResult {
    var diagnostics: [CapabilityDiagnostic] = []

    for rule in artifact.rules {
      switch rule.plan {
      case .literal, .runClassRun, .runHeadTail, .runPrefixed:
        continue
      case .localWindow, .fallback:
        let family = rule.family.rawValue
        let message =
          "artifact-capability-error: unsupported rule family for runtime profile v0, ruleID=\(rule.ruleID), name=\(rule.name), family=\(family)"
        diagnostics.append(
          CapabilityDiagnostic(
            ruleID: rule.ruleID,
            ruleName: rule.name,
            family: family,
            message: message
          ))
      }
    }

    diagnostics.sort { lhs, rhs in
      if lhs.ruleID != rhs.ruleID {
        return lhs.ruleID < rhs.ruleID
      }
      if lhs.ruleName != rhs.ruleName {
        return lhs.ruleName < rhs.ruleName
      }
      return lhs.family < rhs.family
    }

    return ValidationResult(isValid: diagnostics.isEmpty, diagnostics: diagnostics)
  }
}
