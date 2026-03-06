import ArgumentParser
import CustomDump
import Dependencies
import Foundation

struct Doctor: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Print runtime/tooling diagnosis"
  )

  @Flag(name: .shortAndLong, help: "Emit JSON output")
  var json: Bool = false

  struct Report: Codable, Equatable {
    let status: String
    let timestamp: String
    let environment: [String: String]
    let runtime: String
  }

  func run() async throws {
    let deps = DependencyValues._current
    let stdout = deps.stdout
    let environment = deps.env.environment()
    let report = Report(
      status: "ok",
      timestamp: ISO8601DateFormatter().string(from: deps.clock.now()),
      environment: environment,
      runtime: environment["MS_RUNTIME"] ?? ProcessInfo.processInfo.operatingSystemVersionString
    )

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(report)
      stdout.write(String(decoding: data, as: UTF8.self) + "\n")
    } else {
      stdout.write("micro-swift doctor\n")
      stdout.write("status: \(report.status)\n")
      stdout.write("os: \(report.runtime)\n")
      stdout.write("time: \(report.timestamp)\n")
    }
  }
}
