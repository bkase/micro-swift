import ArgumentParser
import Dependencies
import Foundation
import MicroSwiftFrontend
import MicroSwiftLexerGen
import MicroSwiftTensorCore

struct Lex: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "lex",
    abstract: "Run lex-only pipeline and emit structured JSON tokens"
  )

  @Argument(help: "Path to the source file to lex")
  var path: String

  @Flag(name: .long, help: "Include structured observability in the JSON output")
  var observe: Bool = false

  func run() async throws {
    let deps = DependencyValues._current
    let fileData = try deps.fileSystem.readFile(path)
    let source = SourceBuffer(
      fileID: FileID(rawValue: fileID(for: path)),
      path: path,
      bytes: fileData
    )

    let (runtime, lexerArtifact) = try buildRuntimeArtifact()
    let capabilityDiagnostics = CapabilityValidator.validate(artifact: lexerArtifact, profile: .v0)
    guard capabilityDiagnostics.isEmpty else {
      let output = LexFailureOutput(
        status: "artifact-capability-error",
        diagnostics: capabilityDiagnostics.map {
          CapabilityDiagnosticOutput(
            ruleID: $0.ruleID,
            ruleName: $0.ruleName,
            family: $0.family.rawValue,
            message: $0.reason.rawValue
          )
        }
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(output)
      deps.stdout.write(String(decoding: data, as: UTF8.self) + "\n")
      throw ExitCode(1)
    }

    let lexingShell = LexingShell()
    let lexResult = lexingShell.lexSource(
      source: source,
      artifact: runtime,
      options: LexOptions(emitSkipTokens: false)
    )

    let kindByID = Dictionary(
      uniqueKeysWithValues: runtime.tokenKinds.map { ($0.tokenKindID, $0.name) })
    let tokens = lexResult.tokenTape.tokens.map { token in
      TokenOutput(
        kindID: token.kind,
        kind: kindByID[token.kind] ?? "<unknown>",
        startByte: token.startByte,
        endByte: token.endByte,
        flags: token.flags
      )
    }

    let output = LexOutput(
      filePath: path,
      fileID: source.fileID.rawValue,
      tokenCount: tokens.count,
      tokens: tokens,
      errorSpans: lexResult.tokenTape.errorSpans.map {
        ErrorSpanOutput(start: $0.start, end: $0.end)
      },
      overflows: lexResult.tokenTape.overflows.map {
        OverflowOutput(
          message: $0.message,
          pageByteCount: $0.pageByteCount,
          maxBucketSize: $0.maxBucketSize
        )
      },
      observation: observe
        ? StructuredObserver.observe(
          source: source,
          tape: lexResult.tokenTape,
          pages: lexingShell.pagingShell.planAndPreparePages(source: source)
        )
        : nil
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(output)
    deps.stdout.write(String(decoding: data, as: UTF8.self) + "\n")
  }

  private func fileID(for path: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for byte in path.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* 16_777_619
    }
    return hash
  }

  private func buildRuntimeArtifact() throws -> (ArtifactRuntime, LexerArtifact) {
    let declared = microSwiftV0.declare()
    let normalized = DeclaredSpec.normalize(declared)
    let validated = try NormalizedSpec.validate(normalized)
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let classified = try validated.classifyRules(
      byteClasses: byteClasses,
      classSets: classSets
    )
    let artifact = try ArtifactSerializer.build(
      classified: classified,
      byteClasses: byteClasses,
      classSets: classSets,
      generatorVersion: "micro-swift-cli"
    )
    return (try ArtifactLoader.load(artifact), artifact)
  }
}

private struct LexOutput: Codable {
  let filePath: String
  let fileID: UInt32
  let tokenCount: Int
  let tokens: [TokenOutput]
  let errorSpans: [ErrorSpanOutput]
  let overflows: [OverflowOutput]
  let observation: LexObservation?
}

private struct TokenOutput: Codable {
  let kindID: UInt16
  let kind: String
  let startByte: Int64
  let endByte: Int64
  let flags: UInt8
}

private struct ErrorSpanOutput: Codable {
  let start: Int32
  let end: Int32
}

private struct OverflowOutput: Codable {
  let message: String
  let pageByteCount: Int32
  let maxBucketSize: Int32
}

private struct LexFailureOutput: Codable {
  let status: String
  let diagnostics: [CapabilityDiagnosticOutput]
}

private struct CapabilityDiagnosticOutput: Codable {
  let ruleID: UInt16
  let ruleName: String
  let family: String
  let message: String
}
