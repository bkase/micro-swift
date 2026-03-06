/// Whether a rule emits a token or is skipped.
public enum RuleMode: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
  case emit
  case skip
}

/// The role of a rule in the spec.
public enum RuleRole: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
  case token
  case skip
  case identifier
}
