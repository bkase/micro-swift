import ArgumentParser
import Dependencies
import Foundation
import MicroSwiftSpec

struct Seed: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "seed",
    abstract: "Seed utilities",
    subcommands: [SeedDump.self]
  )
}

struct SeedDump: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dump",
    abstract: "Print deterministic seed manifest"
  )

  @Flag(name: .shortAndLong, help: "Emit JSON output")
  var json: Bool = false

  func run() async throws {
    let deps = DependencyValues._current
    let manifestPath = (deps.fileSystem.currentDirectoryPath() as NSString).appendingPathComponent(
      "Config/bench-seeds.json")
    let manifest = try BenchSeedManifest.decode(from: deps.fileSystem.readFile(manifestPath))

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(manifest)
      deps.stdout.write(String(decoding: data, as: UTF8.self) + "\n")
      return
    }

    var lines = [
      "micro-swift seed dump",
      "schemaVersion: \(manifest.schemaVersion)",
      "globalSeed: \(manifest.globalSeed)",
    ]

    for corpus in manifest.corpusSeeds.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
      lines.append("seed(\(corpus.rawValue)): \(manifest.seed(for: corpus))")
    }

    deps.stdout.write(lines.joined(separator: "\n") + "\n")
  }
}
