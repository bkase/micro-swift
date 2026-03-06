import Dependencies
import Foundation
import MLX

public struct ProcessResult: Sendable, Equatable {
  public let exitCode: Int32
  public let stdout: String
  public let stderr: String

  public init(exitCode: Int32, stdout: String, stderr: String) {
    self.exitCode = exitCode
    self.stdout = stdout
    self.stderr = stderr
  }
}

public struct FileSystemClient: Sendable {
  public var currentDirectoryPath: @Sendable () -> String
  public var directoryExists: @Sendable (String) -> Bool
  public var fileExists: @Sendable (String) -> Bool
  public var readFile: @Sendable (String) throws -> Data
  public var writeFile: @Sendable (String, Data) throws -> Void

  public init(
    currentDirectoryPath: @escaping @Sendable () -> String,
    directoryExists: @escaping @Sendable (String) -> Bool,
    fileExists: @escaping @Sendable (String) -> Bool,
    readFile: @escaping @Sendable (String) throws -> Data,
    writeFile: @escaping @Sendable (String, Data) throws -> Void
  ) {
    self.currentDirectoryPath = currentDirectoryPath
    self.directoryExists = directoryExists
    self.fileExists = fileExists
    self.readFile = readFile
    self.writeFile = writeFile
  }

  public static func live() -> Self {
    return Self(
      currentDirectoryPath: { FileManager.default.currentDirectoryPath },
      directoryExists: { path in
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
      },
      fileExists: { FileManager.default.fileExists(atPath: $0) },
      readFile: { try Data(contentsOf: URL(fileURLWithPath: $0)) },
      writeFile: { path, data in
        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
      }
    )
  }

  public static func test(_ fileMap: [String: Data] = [:]) -> Self {
    Self(
      currentDirectoryPath: { "/tmp/micro-swift-tests" },
      directoryExists: { fileMap[$0] != nil },
      fileExists: { fileMap[$0] != nil },
      readFile: { path in
        guard let data = fileMap[path] else {
          throw CocoaError(.fileNoSuchFile)
        }
        return data
      },
      writeFile: { _, _ in }
    )
  }
}

public struct EnvironmentClient: Sendable {
  public var environment: @Sendable () -> [String: String]
  public var osVersion: @Sendable () -> String

  public init(
    environment: @escaping @Sendable () -> [String: String],
    osVersion: @escaping @Sendable () -> String
  ) {
    self.environment = environment
    self.osVersion = osVersion
  }

  public static func live() -> Self {
    Self(
      environment: { ProcessInfo.processInfo.environment },
      osVersion: { ProcessInfo.processInfo.operatingSystemVersionString }
    )
  }

  public static func test(_ values: [String: String] = [:], osVersion: String = "test-os") -> Self {
    Self(environment: { values }, osVersion: { osVersion })
  }
}

public struct ClockClient: Sendable {
  public var now: @Sendable () -> Date
  public var sleep: @Sendable (Duration) async -> Void

  public init(
    now: @escaping @Sendable () -> Date,
    sleep: @escaping @Sendable (Duration) async -> Void
  ) {
    self.now = now
    self.sleep = sleep
  }

  public static func live() -> Self {
    Self(now: { Date() }, sleep: { duration in try? await Task.sleep(for: duration) })
  }

  public static func test(date: Date = Date()) -> Self {
    Self(now: { date }, sleep: { _ in })
  }
}

public struct UUIDClient: Sendable {
  public var make: @Sendable () -> String

  public init(make: @escaping @Sendable () -> String) {
    self.make = make
  }

  public static func live() -> Self {
    Self(make: { UUID().uuidString })
  }

  public static func test(value: String = "TEST-UUID") -> Self {
    Self(make: { value })
  }
}

public struct ProcessClient: Sendable {
  public var run: @Sendable (String, [String]) async throws -> ProcessResult

  public init(run: @escaping @Sendable (String, [String]) async throws -> ProcessResult) {
    self.run = run
  }

  public static func live() -> Self {
    Self(
      run: { executable, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        process.waitUntilExit()

        let stdoutData = try out.fileHandleForReading.readToEnd() ?? Data()
        let stderrData = try err.fileHandleForReading.readToEnd() ?? Data()

        return ProcessResult(
          exitCode: process.terminationStatus,
          stdout: String(decoding: stdoutData, as: UTF8.self),
          stderr: String(decoding: stderrData, as: UTF8.self)
        )
      }
    )
  }

  public static func test(
    result: ProcessResult = ProcessResult(exitCode: 0, stdout: "", stderr: "")
  ) -> Self {
    Self(run: { _, _ in result })
  }
}

public struct OutputClient: Sendable {
  public var write: @Sendable (String) -> Void

  public init(write: @escaping @Sendable (String) -> Void) {
    self.write = write
  }

  public static func live() -> Self {
    Self(write: { print($0, terminator: "") })
  }
}

public struct MLXRuntimeClient: Sendable {
  public struct MLXSmokeResult: Codable, Sendable, Equatable {
    public let status: String
    public let kernel: String
    public let version: String

    public init(status: String, kernel: String, version: String) {
      self.status = status
      self.kernel = kernel
      self.version = version
    }
  }

  public var smoke: @Sendable () async throws -> MLXSmokeResult

  public init(smoke: @escaping @Sendable () async throws -> MLXSmokeResult) {
    self.smoke = smoke
  }

  public static func live() -> Self {
    Self {
      let a = MLXArray([1.0, 2.0])
      let b = MLXArray([3.0, 4.0])
      let c = a + b
      eval(c)
      let values = c.asArray(Float.self)
      guard values == [4.0, 6.0] else {
        throw MLXSmokeError.unexpectedResult(values)
      }
      return MLXSmokeResult(
        status: "ok",
        kernel: "trivial-add",
        version: "mlx-swift"
      )
    }
  }

  enum MLXSmokeError: Error {
    case unexpectedResult([Float])
  }

  public static func test(
    result: MLXSmokeResult = MLXSmokeResult(status: "ok", kernel: "trivial-add", version: "test")
  ) -> Self {
    Self { result }
  }
}

private enum FileSystemClientKey: DependencyKey {
  static let liveValue = FileSystemClient.live()
}

private enum EnvironmentClientKey: DependencyKey {
  static let liveValue = EnvironmentClient.live()
}

private enum ClockClientKey: DependencyKey {
  static let liveValue = ClockClient.live()
}

private enum UUIDClientKey: DependencyKey {
  static let liveValue = UUIDClient.live()
}

private enum ProcessClientKey: DependencyKey {
  static let liveValue = ProcessClient.live()
}

private enum StdoutKey: DependencyKey {
  static let liveValue = OutputClient.live()
}

private enum StderrKey: DependencyKey {
  static let liveValue = OutputClient.live()
}

private enum MLXRuntimeClientKey: DependencyKey {
  static let liveValue = MLXRuntimeClient.live()
}

extension DependencyValues {
  public var fileSystem: FileSystemClient {
    get { self[FileSystemClientKey.self] }
    set { self[FileSystemClientKey.self] = newValue }
  }

  public var env: EnvironmentClient {
    get { self[EnvironmentClientKey.self] }
    set { self[EnvironmentClientKey.self] = newValue }
  }

  public var clock: ClockClient {
    get { self[ClockClientKey.self] }
    set { self[ClockClientKey.self] = newValue }
  }

  public var uuid: UUIDClient {
    get { self[UUIDClientKey.self] }
    set { self[UUIDClientKey.self] = newValue }
  }

  public var process: ProcessClient {
    get { self[ProcessClientKey.self] }
    set { self[ProcessClientKey.self] = newValue }
  }

  public var stdout: OutputClient {
    get { self[StdoutKey.self] }
    set { self[StdoutKey.self] = newValue }
  }

  public var stderr: OutputClient {
    get { self[StderrKey.self] }
    set { self[StderrKey.self] = newValue }
  }

  public var mlxRuntime: MLXRuntimeClient {
    get { self[MLXRuntimeClientKey.self] }
    set { self[MLXRuntimeClientKey.self] = newValue }
  }
}
