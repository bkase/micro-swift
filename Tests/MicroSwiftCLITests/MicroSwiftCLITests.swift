import ArgumentParser
import CustomDump
import Dependencies
import Foundation
import SnapshotTesting
import Testing

@testable import MicroSwiftCLI

/// Runs `operation` with common test dependency defaults installed.
/// Individual tests can supply additional overrides via `extraDeps`.
private func withTestDependencies(
  _ output: TestOutputCapture,
  extraDeps: @escaping (inout DependencyValues) -> Void = { _ in },
  operation: @escaping @Sendable () async throws -> Void
) async throws {
  try await withDependencies {
    $0.stdout = OutputClient(write: { output.append($0) })
    $0.stderr = OutputClient(write: { _ in })
    $0.env = EnvironmentClient.test(["MS_TEST": "1", "MS_RUNTIME": "test-runtime"])
    $0.clock = ClockClient.test(date: Date(timeIntervalSince1970: 1_703_846_000))
    $0.uuid = UUIDClient.test(value: "00000000-0000-0000-0000-000000000000")
    $0.mlxRuntime = MLXRuntimeClient.test(
      result: MLXRuntimeClient.MLXSmokeResult(
        status: "ok", kernel: "trivial-add", version: "deterministic-mock")
    )
    extraDeps(&$0)
  } operation: {
    try await operation()
  }
}

@Suite
struct MicroSwiftCLITests {
  @Test func helpIsStable() async throws {
    let helpText = MicroSwift.helpMessage()
    assertSnapshot(of: helpText, as: .lines)
  }

  @Test func doctorJsonIsStable() async throws {
    let output = TestOutputCapture()
    try await withTestDependencies(output) {
      let command = try MicroSwift.parseAsRoot(["doctor", "--json"])
      var asyncCommand = try #require(command as? any AsyncParsableCommand)
      try await asyncCommand.run()
    }

    assertSnapshot(of: output.text(), as: .lines)
  }

  @Test func doctorTextIsStable() async throws {
    let output = TestOutputCapture()
    try await withTestDependencies(output) {
      let command = try MicroSwift.parseAsRoot(["doctor"])
      var asyncCommand = try #require(command as? any AsyncParsableCommand)
      try await asyncCommand.run()
    }

    assertSnapshot(of: output.text(), as: .lines)
  }

  @Test func seedDumpJsonIsStable() async throws {
    let testRoot = "/tmp/micro-swift-tests"
    let fixturePath = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Config/bench-seeds.json")
    let path = (testRoot as NSString).appendingPathComponent("Config/bench-seeds.json")
    let fileMap: [String: Data] = [
      path: try! Data(contentsOf: fixturePath)
    ]

    let output = TestOutputCapture()
    try await withTestDependencies(output, extraDeps: {
      $0.fileSystem = FileSystemClient.test(fileMap)
    }, operation: {
      let command = try MicroSwift.parseAsRoot(["seed", "dump", "--json"])
      var asyncCommand = try #require(command as? any AsyncParsableCommand)
      try await asyncCommand.run()
    })

    assertSnapshot(of: output.text(), as: .json)
  }

  @Test func seedDumpTextIsStable() async throws {
    let testRoot = "/tmp/micro-swift-tests"
    let fixturePath = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Config/bench-seeds.json")
    let path = (testRoot as NSString).appendingPathComponent("Config/bench-seeds.json")
    let fileMap: [String: Data] = [
      path: try! Data(contentsOf: fixturePath)
    ]

    let output = TestOutputCapture()
    try await withTestDependencies(output, extraDeps: {
      $0.fileSystem = FileSystemClient.test(fileMap)
    }, operation: {
      let command = try MicroSwift.parseAsRoot(["seed", "dump"])
      var asyncCommand = try #require(command as? any AsyncParsableCommand)
      try await asyncCommand.run()
    })

    assertSnapshot(of: output.text(), as: .lines)
  }

  @Test func mlxSmokeJsonIsStable() async throws {
    let output = TestOutputCapture()
    try await withTestDependencies(output) {
      let command = try MicroSwift.parseAsRoot(["mlx-smoke", "--json"])
      var asyncCommand = try #require(command as? any AsyncParsableCommand)
      try await asyncCommand.run()
    }

    assertSnapshot(of: output.text(), as: .json)
  }

  @Test func mlxSmokeTextIsStable() async throws {
    let output = TestOutputCapture()
    try await withTestDependencies(output) {
      let command = try MicroSwift.parseAsRoot(["mlx-smoke"])
      var asyncCommand = try #require(command as? any AsyncParsableCommand)
      try await asyncCommand.run()
    }

    assertSnapshot(of: output.text(), as: .lines)
  }
}
