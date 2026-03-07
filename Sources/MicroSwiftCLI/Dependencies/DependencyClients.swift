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
    public let fallbackRuleCount: Int
    public let artifactHash: String
    public let fastPathBackendIdentifier: String
    public let fastPathDeviceIdentifier: String
    public let fastPathPipelineIdentifier: String
    public let fastPathGraphCompileCount: Int
    public let fastPathGraphCacheHitCount: Int
    public let fastPathGraphCacheMissCount: Int
    public let forbiddenMidPipelineHostExtractionCount: Int
    public let runFamilyBackendIdentifier: String
    public let runFamilyClassRunDispatchCount: Int
    public let runFamilyHeadTailDispatchCount: Int
    public let literalWorkloadRowCount: Int
    public let runWorkloadRowCount: Int
    public let prefixedWorkloadRowCount: Int
    public let fixtureIdentifier: String

    public init(
      status: String,
      runtimeProfile: String,
      fallbackRuleCount: Int,
      artifactHash: String,
      fastPathBackendIdentifier: String,
      fastPathDeviceIdentifier: String,
      fastPathPipelineIdentifier: String,
      fastPathGraphCompileCount: Int,
      fastPathGraphCacheHitCount: Int,
      fastPathGraphCacheMissCount: Int,
      forbiddenMidPipelineHostExtractionCount: Int,
      runFamilyBackendIdentifier: String,
      runFamilyClassRunDispatchCount: Int,
      runFamilyHeadTailDispatchCount: Int,
      literalWorkloadRowCount: Int,
      runWorkloadRowCount: Int,
      prefixedWorkloadRowCount: Int,
      fixtureIdentifier: String
    ) {
      self.status = status
      self.runtimeProfile = runtimeProfile
      self.fallbackRuleCount = fallbackRuleCount
      self.artifactHash = artifactHash
      self.fastPathBackendIdentifier = fastPathBackendIdentifier
      self.fastPathDeviceIdentifier = fastPathDeviceIdentifier
      self.fastPathPipelineIdentifier = fastPathPipelineIdentifier
      self.fastPathGraphCompileCount = fastPathGraphCompileCount
      self.fastPathGraphCacheHitCount = fastPathGraphCacheHitCount
      self.fastPathGraphCacheMissCount = fastPathGraphCacheMissCount
      self.forbiddenMidPipelineHostExtractionCount = forbiddenMidPipelineHostExtractionCount
      self.runFamilyBackendIdentifier = runFamilyBackendIdentifier
      self.runFamilyClassRunDispatchCount = runFamilyClassRunDispatchCount
      self.runFamilyHeadTailDispatchCount = runFamilyHeadTailDispatchCount
      self.literalWorkloadRowCount = literalWorkloadRowCount
      self.runWorkloadRowCount = runWorkloadRowCount
      self.prefixedWorkloadRowCount = prefixedWorkloadRowCount
      self.fixtureIdentifier = fixtureIdentifier
    }
  }

  public var smoke: @Sendable () async throws -> MLXSmokeResult

  public init(smoke: @escaping @Sendable () async throws -> MLXSmokeResult) {
    self.smoke = smoke
  }

  public static func live() -> Self {
    Self {
      let fixtureIdentifier = "mlx-smoke-proof-literal-run-prefixed-v1"
      let fallbackArtifact = try buildFallbackSmokeArtifact()
      let fallbackRuntime = try ArtifactRuntime.fromArtifact(fallbackArtifact)
      let smokeInputBytes = try makeFallbackHeavySmokeInput(runtime: fallbackRuntime)

      let benchmark = runBenchmark(
        bytes: smokeInputBytes,
        artifact: fallbackRuntime,
        config: BenchmarkConfig(mode: .warm, iterations: 2, seed: 0x5EED)
      )

      guard benchmark.fallbackRuleCount > 0 else {
        throw MLXSmokeError.noFallbackRulesPresent
      }

      let fastLiteralArtifact = try buildFastLiteralSmokeArtifact()
      let fastRunArtifact = try buildFastRunSmokeArtifact()
      let fastPrefixedArtifact = try buildFastPrefixedSmokeArtifact()
      let fastLiteralRuntime = try ArtifactRuntime.fromArtifact(fastLiteralArtifact)
      let fastRunRuntime = try ArtifactRuntime.fromArtifact(fastRunArtifact)
      let fastPrefixedRuntime = try ArtifactRuntime.fromArtifact(fastPrefixedArtifact)

      let literalInput = Array("aaaaaaaaaaaa".utf8)
      let runInput = Array("alpha beta gamma42 delta99 _omega123".utf8)
      let prefixedInput = Array("//aaaa\n//bbbb\n//cccc\n".utf8)

      TensorLexer.resetFastPathGraphCache()
      CompiledPageInput.resetHostExtractionCounts()
      ClassRunExecution.resetDispatchMetrics()

      let literalRows = try runFastPathProofWorkload(
        bytes: literalInput,
        runtime: fastLiteralRuntime
      )
      let runRows = try runFastPathProofWorkload(
        bytes: runInput,
        runtime: fastRunRuntime
      )
      let prefixedRows = try runFastPathProofWorkload(
        bytes: prefixedInput,
        runtime: fastPrefixedRuntime
      )

      guard literalRows > 0 else {
        throw MLXSmokeError.missingLiteralWorkloadCoverage
      }
      guard runRows > 0 else {
        throw MLXSmokeError.missingRunWorkloadCoverage
      }
      guard prefixedRows > 0 else {
        throw MLXSmokeError.missingPrefixedWorkloadCoverage
      }

      let fastPathMetrics = TensorLexer.fastPathGraphMetrics()
      guard fastPathMetrics.compileCount == 3 else {
        throw MLXSmokeError.missingFastPathWarmReuse
      }
      guard fastPathMetrics.cacheMisses == 3 else {
        throw MLXSmokeError.missingFastPathWarmReuse
      }
      guard fastPathMetrics.cacheHits >= 3 else {
        throw MLXSmokeError.missingFastPathWarmReuse
      }

      let fastPathStoreEvent = fastPathMetrics.cacheEvents.first {
        ($0.event == "fast-path-graph-cache-store" || $0.event == "fast-path-graph-cache-hit")
          && $0.runtimeMetadata != nil
      }
      guard let fastPathMetadata = fastPathStoreEvent?.runtimeMetadata else {
        throw MLXSmokeError.missingFastPathRuntimeMetadata
      }
      guard fastPathMetadata.backend.hasPrefix("mlx") else {
        throw MLXSmokeError.unexpectedBackend(fastPathMetadata.backend)
      }
      guard fastPathMetadata.pipelineFunction == "fastPathPageGraph" else {
        throw MLXSmokeError.unexpectedPipeline(fastPathMetadata.pipelineFunction)
      }

      let hostExtractionCounts = CompiledPageInput.hostExtractionCounts()
      guard hostExtractionCounts.transitionalFamilyExecution == 0 else {
        throw MLXSmokeError.forbiddenMidPipelineHostExtraction(
          hostExtractionCounts.transitionalFamilyExecution)
      }

      let runFamilyMetrics = ClassRunExecution.dispatchMetrics()

      return MLXSmokeResult(
        status: "ok",
        runtimeProfile: "fallback-benchmark-warm",
        fallbackRuleCount: benchmark.fallbackRuleCount,
        artifactHash: fallbackRuntime.artifactHash,
        fastPathBackendIdentifier: fastPathMetadata.backend,
        fastPathDeviceIdentifier: fastPathMetadata.deviceID,
        fastPathPipelineIdentifier: fastPathMetadata.pipelineFunction,
        fastPathGraphCompileCount: fastPathMetrics.compileCount,
        fastPathGraphCacheHitCount: fastPathMetrics.cacheHits,
        fastPathGraphCacheMissCount: fastPathMetrics.cacheMisses,
        forbiddenMidPipelineHostExtractionCount: hostExtractionCounts.transitionalFamilyExecution,
        runFamilyBackendIdentifier: ClassRunExecution.backendNameForTesting(),
        runFamilyClassRunDispatchCount: runFamilyMetrics.classRunDispatches,
        runFamilyHeadTailDispatchCount: runFamilyMetrics.headTailDispatches,
        literalWorkloadRowCount: literalRows,
        runWorkloadRowCount: runRows,
        prefixedWorkloadRowCount: prefixedRows,
        fixtureIdentifier: fixtureIdentifier
      )
    }
  }

  enum MLXSmokeError: Error {
    case noFallbackRulesPresent
    case missingFastPathRuntimeMetadata
    case missingFastPathWarmReuse
    case forbiddenMidPipelineHostExtraction(Int)
    case missingRunFamilyClassRunDispatch
    case missingRunFamilyHeadTailDispatch
    case missingLiteralWorkloadCoverage
    case missingRunWorkloadCoverage
    case missingPrefixedWorkloadCoverage
    case unexpectedBackend(String)
    case unexpectedPipeline(String)
  }

  public static func test(
    result: MLXSmokeResult = MLXSmokeResult(
      status: "ok",
      runtimeProfile: "fallback-benchmark-warm",
      fallbackRuleCount: 1,
      artifactHash: "deadbeefcafebabe",
      fastPathBackendIdentifier: "mlx",
      fastPathDeviceIdentifier: "mlx-cpu",
      fastPathPipelineIdentifier: "fastPathPageGraph",
      fastPathGraphCompileCount: 3,
      fastPathGraphCacheHitCount: 3,
      fastPathGraphCacheMissCount: 3,
      forbiddenMidPipelineHostExtractionCount: 0,
      runFamilyBackendIdentifier: "metal-test-device",
      runFamilyClassRunDispatchCount: 6,
      runFamilyHeadTailDispatchCount: 6,
      literalWorkloadRowCount: 5,
      runWorkloadRowCount: 5,
      prefixedWorkloadRowCount: 3,
      fixtureIdentifier: "mlx-smoke-proof-literal-run-prefixed-v1"
    )
  ) -> Self {
    Self { result }
  }
}

private func runFastPathProofWorkload(bytes: [UInt8], runtime: ArtifactRuntime) throws -> Int {
  guard !bytes.isEmpty else { return 0 }
  let options = LexOptions(runtimeProfile: .v0)
  let first = TensorLexer.lexPage(
    bytes: bytes,
    validLen: Int32(bytes.count),
    baseOffset: 0,
    artifact: runtime,
    options: options
  )
  let second = TensorLexer.lexPage(
    bytes: bytes,
    validLen: Int32(bytes.count),
    baseOffset: 0,
    artifact: runtime,
    options: options
  )
  guard first == second else {
    throw MLXRuntimeClient.MLXSmokeError.missingFastPathWarmReuse
  }
  return Int(second.rowCount)
}

private func makeFallbackHeavySmokeInput(runtime: ArtifactRuntime) throws -> [UInt8] {
  guard let fallback = runtime.fallback else {
    throw MLXRuntimeClient.MLXSmokeError.noFallbackRulesPresent
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
    throw MLXRuntimeClient.MLXSmokeError.noFallbackRulesPresent
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

private func buildFastLiteralSmokeArtifact() throws -> LexerArtifact {
  let spec = LexerSpec(name: "mlx.smoke.fast.literal") {
    token("letterA", literal("a"))
  }
  let declared = spec.declare()
  let normalized = DeclaredSpec.normalize(declared)
  let validated = try NormalizedSpec.validate(normalized)
  let byteClasses = validated.buildByteClasses()
  let classSets = validated.buildClassSets(using: byteClasses)
  let classified = try validated.classifyRules(
    byteClasses: byteClasses,
    classSets: classSets
  )
  return try ArtifactSerializer.build(
    classified: classified,
    byteClasses: byteClasses,
    classSets: classSets,
    generatorVersion: "micro-swift-cli-fast-literal-smoke"
  )
}

private func buildFastRunSmokeArtifact() throws -> LexerArtifact {
  let spec = LexerSpec(name: "mlx.smoke.fast.run") {
    token("ident", .byteClass(.asciiIdentStart) <> zeroOrMore(.byteClass(.asciiIdentContinue)))
    token("int", oneOrMore(.byteClass(.asciiDigit)))
    skip("ws", oneOrMore(.byteClass(.asciiWhitespace)))
  }
  let declared = spec.declare()
  let normalized = DeclaredSpec.normalize(declared)
  let validated = try NormalizedSpec.validate(normalized)
  let byteClasses = validated.buildByteClasses()
  let classSets = validated.buildClassSets(using: byteClasses)
  let classified = try validated.classifyRules(
    byteClasses: byteClasses,
    classSets: classSets
  )
  return try ArtifactSerializer.build(
    classified: classified,
    byteClasses: byteClasses,
    classSets: classSets,
    generatorVersion: "micro-swift-cli-fast-run-smoke"
  )
}

private func buildFastPrefixedSmokeArtifact() throws -> LexerArtifact {
  let spec = LexerSpec(name: "mlx.smoke.fast.prefixed") {
    token("lineComment", literal("//") <> zeroOrMore(not(.newline)))
    token("newline", literal("\n"))
  }
  let declared = spec.declare()
  let normalized = DeclaredSpec.normalize(declared)
  let validated = try NormalizedSpec.validate(normalized)
  let byteClasses = validated.buildByteClasses()
  let classSets = validated.buildClassSets(using: byteClasses)
  let classified = try validated.classifyRules(
    byteClasses: byteClasses,
    classSets: classSets
  )
  return try ArtifactSerializer.build(
    classified: classified,
    byteClasses: byteClasses,
    classSets: classSets,
    generatorVersion: "micro-swift-cli-fast-prefixed-smoke"
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
