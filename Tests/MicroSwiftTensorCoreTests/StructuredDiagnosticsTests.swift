import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct StructuredDiagnosticsTests {
  @Test
  func eachRejectionReasonRendersExpectedDescriptionFormat() {
    for reason in allReasons {
      let family: RuleFamily = reason == .localWindowPresent ? .localWindow : .fallback
      let diagnostic = CapabilityDiagnostic(
        ruleID: 42,
        ruleName: "sampleRule",
        family: family,
        reason: reason
      )

      #expect(
        diagnostic.description
          == "artifact-capability-error: unsupported \(family.rawValue) ruleID=42 name=sampleRule reason=\(reason.rawValue)"
      )
    }
  }

  @Test
  func formattedMessageIncludesRequiredStructuredFields() {
    let diagnostic = CapabilityDiagnostic(
      ruleID: 77,
      ruleName: "windowRule",
      family: .localWindow,
      reason: .localWindowPresent
    )

    let message = diagnostic.formattedMessage(profile: .v1Fallback)

    #expect(message.contains("artifact-capability-error:"))
    #expect(message.contains("unsupported localWindow"))
    #expect(message.contains("runtime profile v1-fallback"))
    #expect(message.contains("ruleID=77"))
    #expect(message.contains("name=windowRule"))
    #expect(message.contains("reason=localWindow-present"))
  }
}

private let allReasons: [CapabilityRejectionReason] = [
  .stateCapExceeded,
  .missingTable,
  .widthExceeded,
  .maxLookaheadMismatch,
  .localWindowPresent,
]
