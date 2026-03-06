import ArgumentParser
import Dependencies
import Foundation
import MicroSwiftLexerGen

struct LexerGen: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "lexergen",
    abstract: "Generate and check lexer artifacts",
    subcommands: [LexerGenDump.self, LexerGenCheck.self]
  )
}

struct LexerGenDump: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dump",
    abstract: "Print canonical lexer artifact JSON"
  )

  @Flag(name: .shortAndLong, help: "Emit pretty-printed JSON")
  var pretty: Bool = false

  @Option(name: .shortAndLong, help: "Write output to file instead of stdout")
  var output: String?

  func run() async throws {
    let deps = DependencyValues._current
    let artifact = try buildMicroSwiftV0Artifact()
    let data: Data
    if pretty {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      data = try encoder.encode(artifact)
    } else {
      data = try ArtifactSerializer.encode(artifact)
    }

    if let output {
      try deps.fileSystem.writeFile(output, data)
      deps.stdout.write("lexergen dump: wrote \(output)\n")
    } else {
      deps.stdout.write(String(decoding: data, as: UTF8.self) + "\n")
    }
  }
}

struct LexerGenCheck: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check",
    abstract: "Compare generated artifact to an on-disk artifact"
  )

  @Option(name: .shortAndLong, help: "Artifact path to compare against")
  var path: String = "Artifacts/MicroSwift.v0.lexer.json"

  func run() async throws {
    let deps = DependencyValues._current
    let expected = try buildMicroSwiftV0Artifact()
    let data = try deps.fileSystem.readFile(path)
    let actual = try ArtifactSerializer.decode(data)

    if actual == expected {
      deps.stdout.write("lexergen check: ok\n")
    } else {
      deps.stdout.write("lexergen check: mismatch\n")
      throw ExitCode(1)
    }
  }
}

private func buildMicroSwiftV0Artifact() throws -> LexerArtifact {
  let options = CompileOptions(
    maxLocalWindowBytes: 8, enableFallback: true, maxFallbackStatesPerRule: 256)
  let declared = microSwiftV0.declare()
  let normalized = DeclaredSpec.normalize(declared)
  let validated = try NormalizedSpec.validate(normalized, options: options)
  let byteClasses = validated.buildByteClasses()
  let classSets = validated.buildClassSets(using: byteClasses)
  let classified = try validated.classifyRules(
    byteClasses: byteClasses, classSets: classSets, options: options)
  return try ArtifactSerializer.build(
    classified: classified,
    byteClasses: byteClasses,
    classSets: classSets,
    generatorVersion: "micro-swift-cli"
  )
}
