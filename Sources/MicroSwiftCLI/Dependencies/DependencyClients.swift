import Dependencies
import Foundation
import MicroSwiftLexerGen
import MicroSwiftTensorCore

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
    public let runtimeProfile: String
    public let backendIdentifier: String
    public let deviceIdentifier: String
    public let kernelPipelineIdentifier: String
    public let fallbackPositionsEntered: Int
    public let fallbackPositionsSkippedByStartMask: Int
    public let fallbackKernelExecutionCount: Int
    public let artifactHash: String
    public let fixtureIdentifier: String

    public init(
      status: String,
      runtimeProfile: String,
      backendIdentifier: String,
      deviceIdentifier: String,
      kernelPipelineIdentifier: String,
      fallbackPositionsEntered: Int,
      fallbackPositionsSkippedByStartMask: Int,
      fallbackKernelExecutionCount: Int,
      artifactHash: String,
      fixtureIdentifier: String
    ) {
      self.status = status
      self.runtimeProfile = runtimeProfile
      self.backendIdentifier = backendIdentifier
      self.deviceIdentifier = deviceIdentifier
      self.kernelPipelineIdentifier = kernelPipelineIdentifier
      self.fallbackPositionsEntered = fallbackPositionsEntered
      self.fallbackPositionsSkippedByStartMask = fallbackPositionsSkippedByStartMask
      self.fallbackKernelExecutionCount = fallbackKernelExecutionCount
      self.artifactHash = artifactHash
      self.fixtureIdentifier = fixtureIdentifier
    }
  }

  public var smoke: @Sendable () async throws -> MLXSmokeResult

  public init(smoke: @escaping @Sendable () async throws -> MLXSmokeResult) {
    self.smoke = smoke
  }

  public static func live() -> Self {
    Self {
      let fixtureIdentifier = "mlx-smoke-fallback-alt-ab-cd-v1"
      let artifact = try buildFallbackSmokeArtifact()
      let runtime = try ArtifactRuntime.fromArtifact(artifact)
      let smokeInputBytes = try makeFallbackHeavySmokeInput(runtime: runtime)
      let benchmark = runBenchmark(
        bytes: smokeInputBytes,
        artifact: runtime,
        config: BenchmarkConfig(mode: .warm, iterations: 2, seed: 0x5EED)
      )

      guard benchmark.fallbackPositionsEntered > 0 else {
        throw MLXSmokeError.noFallbackPositionsEntered
      }
      guard benchmark.fallbackKernelBackendDispatches > 0 else {
        throw MLXSmokeError.noFallbackKernelDispatch
      }

      let cacheEvent = benchmark.cacheEvents.first {
        ($0.event == "fallback-kernel-cache-store" || $0.event == "fallback-kernel-cache-hit")
          && $0.runtimeMetadata != nil
      }
      guard let metadata = cacheEvent?.runtimeMetadata else {
        throw MLXSmokeError.missingRuntimeMetadata
      }
      guard metadata.backend == "metal" else {
        throw MLXSmokeError.unexpectedBackend(metadata.backend)
      }
      guard metadata.pipelineFunction == "fallbackKernel" else {
        throw MLXSmokeError.unexpectedPipeline(metadata.pipelineFunction)
      }

      return MLXSmokeResult(
        status: "ok",
        runtimeProfile: "fallback-benchmark-warm",
        backendIdentifier: metadata.backend,
        deviceIdentifier: metadata.deviceID,
        kernelPipelineIdentifier: metadata.pipelineFunction,
        fallbackPositionsEntered: benchmark.fallbackPositionsEntered,
        fallbackPositionsSkippedByStartMask: benchmark.fallbackPositionsSkippedByStartMask,
        fallbackKernelExecutionCount: benchmark.fallbackKernelBackendDispatches,
        artifactHash: cacheEvent?.artifactHash ?? "unknown",
        fixtureIdentifier: fixtureIdentifier
      )
    }
  }

  enum MLXSmokeError: Error {
    case noFallbackPositionsEntered
    case noFallbackKernelDispatch
    case missingRuntimeMetadata
    case unexpectedBackend(String)
    case unexpectedPipeline(String)
  }

  public static func test(
    result: MLXSmokeResult = MLXSmokeResult(
      status: "ok",
      runtimeProfile: "fallback-benchmark-warm",
      backendIdentifier: "metal",
      deviceIdentifier: "metal-test-device",
      kernelPipelineIdentifier: "fallbackKernel",
      fallbackPositionsEntered: 32,
      fallbackPositionsSkippedByStartMask: 8,
      fallbackKernelExecutionCount: 2,
      artifactHash: "deadbeefcafebabe",
      fixtureIdentifier: "mlx-smoke-fallback-alt-ab-cd-v1"
    )
  ) -> Self {
    Self { result }
  }
}

private func makeFallbackHeavySmokeInput(runtime: ArtifactRuntime) throws -> [UInt8] {
  guard let fallback = runtime.fallback else {
    throw MLXRuntimeClient.MLXSmokeError.noFallbackPositionsEntered
  }

  let byteToClass = runtime.hostByteToClassLUT()
  var eligibleByte: UInt8?
  var ineligibleByte: UInt8?

  for candidate in UInt8.min...UInt8.max {
    let classID = byteToClass[Int(candidate)]
    let isEligible: Bool
    if classID < 64 {
      let mask = UInt64(1) << UInt64(classID)
      isEligible = (fallback.startClassMaskLo & mask) != 0
    } else if classID < 128 {
      let mask = UInt64(1) << UInt64(classID - 64)
      isEligible = (fallback.startClassMaskHi & mask) != 0
    } else {
      isEligible = false
    }

    if isEligible {
      eligibleByte = candidate
    } else if ineligibleByte == nil {
      ineligibleByte = candidate
    }

    if eligibleByte != nil, ineligibleByte != nil {
      break
    }
  }

  guard let eligibleByte else {
    throw MLXRuntimeClient.MLXSmokeError.noFallbackPositionsEntered
  }

  let spacer = ineligibleByte ?? 0x20
  var bytes: [UInt8] = []
  bytes.reserveCapacity(512)

  for _ in 0..<128 {
    bytes.append(eligibleByte)
    bytes.append(spacer)
  }

  return bytes
}

private func buildFallbackSmokeArtifact() throws -> LexerArtifact {
  let spec = LexerSpec(name: "mlx.smoke.fallback") {
    token("alt", alt(literal("ab"), literal("cd")))
  }
  let options = CompileOptions(
    maxLocalWindowBytes: 1,
    enableFallback: true,
    maxFallbackStatesPerRule: 256
  )
  let declared = spec.declare()
  let normalized = DeclaredSpec.normalize(declared)
  let validated = try NormalizedSpec.validate(normalized, options: options)
  let byteClasses = validated.buildByteClasses()
  let classSets = validated.buildClassSets(using: byteClasses)
  let classified = try validated.classifyRules(
    byteClasses: byteClasses,
    classSets: classSets,
    options: options
  )

  return try ArtifactSerializer.build(
    classified: classified,
    byteClasses: byteClasses,
    classSets: classSets,
    generatorVersion: "micro-swift-cli-fallback-smoke"
  )
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
