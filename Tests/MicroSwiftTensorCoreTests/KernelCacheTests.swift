import Foundation
import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct KernelCacheTests {
  @Test(.enabled(if: requiresMLXEval))
  func cacheMissThenHit() throws {
    let sink = LogSink()
    let cache = KernelCache(logSink: sink.record)
    let key = makeKey(pageBucket: 128, inputDType: "uint16")
    let metadata = makeRuntimeMetadata(deviceID: key.deviceID)
    let runtime = try makeLiteralRuntime()
    let graph = FastPathCompiledGraph(pageSize: 128, artifact: runtime)

    let firstLookup = cache.lookup(key: key, traceID: "trace-miss")
    #expect(firstLookup == nil)

    cache.store(
      key: key,
      entry: KernelCacheEntry(
        fastPathGraph: graph,
        runtimeMetadata: metadata,
        createdAt: Date(timeIntervalSince1970: 10)
      ),
      traceID: "trace-store"
    )

    let secondLookup = cache.lookup(key: key, traceID: "trace-hit")
    let entry = try #require(secondLookup)
    #expect(entry.fastPathGraph != nil)
    #expect(entry.runtimeMetadata == metadata)

    let records = sink.snapshot()
    #expect(records.count == 3)

    let miss = try decode(records[0])
    #expect(miss.traceID == "trace-miss")
    #expect(miss.event == "fallback-kernel-cache-miss")
    #expect(miss.artifactHash == key.artifactHash)
    #expect(miss.pageBucket == key.pageBucket)
    #expect(miss.deviceID == key.deviceID)
    #expect(miss.inputDType == key.inputDType)
    #expect(miss.runtimeProfile == key.runtimeProfile)
    #expect(miss.layoutSignature == key.layoutSignature)
    #expect(miss.runtimeMetadata == nil)
    #expect(miss.failureReason == nil)

    let store = try decode(records[1])
    #expect(store.traceID == "trace-store")
    #expect(store.event == "fallback-kernel-cache-store")
    #expect(store.runtimeMetadata == metadata)

    let hit = try decode(records[2])
    #expect(hit.traceID == "trace-hit")
    #expect(hit.event == "fallback-kernel-cache-hit")
    #expect(hit.runtimeMetadata == metadata)
  }

  @Test(.enabled(if: requiresMLXEval))
  func differentKeysReturnDifferentEntries() throws {
    let cache = KernelCache()
    let keyA = makeKey(pageBucket: 64, inputDType: "uint16")
    let keyB = makeKey(pageBucket: 128, inputDType: "float16")

    let runtime = try makeLiteralRuntime()
    let graphA = FastPathCompiledGraph(pageSize: 64, artifact: runtime)
    let graphB = FastPathCompiledGraph(pageSize: 128, artifact: runtime)

    cache.store(
      key: keyA,
      entry: KernelCacheEntry(
        fastPathGraph: graphA,
        runtimeMetadata: makeRuntimeMetadata(deviceID: keyA.deviceID),
        createdAt: Date(timeIntervalSince1970: 100)
      )
    )
    cache.store(
      key: keyB,
      entry: KernelCacheEntry(
        fastPathGraph: graphB,
        runtimeMetadata: makeRuntimeMetadata(deviceID: keyB.deviceID),
        createdAt: Date(timeIntervalSince1970: 200)
      )
    )

    let entryA = try #require(cache.lookup(key: keyA, traceID: "trace-a"))
    let entryB = try #require(cache.lookup(key: keyB, traceID: "trace-b"))

    #expect(entryA.fastPathGraph != nil)
    #expect(entryB.fastPathGraph != nil)
    #expect(entryA.createdAt != entryB.createdAt)
    #expect(entryA.runtimeMetadata.deviceID == keyA.deviceID)
    #expect(entryB.runtimeMetadata.deviceID == keyB.deviceID)
  }

  @Test(.enabled(if: requiresMLXEval))
  func structuredLogOutputFormat() throws {
    let sink = LogSink()
    let cache = KernelCache(logSink: sink.record)
    let key = makeKey(pageBucket: 256, inputDType: "uint16")

    enum TestError: Error {
      case creationFailed
    }

    #expect(throws: TestError.creationFailed) {
      _ = try cache.getOrCreate(key: key, traceID: "trace-failure") {
        throw TestError.creationFailed
      }
    }

    let records = sink.snapshot()
    #expect(records.count == 2)

    let miss = try decode(records[0])
    #expect(miss.traceID == "trace-failure")
    #expect(miss.event == "fallback-kernel-cache-miss")
    #expect(miss.artifactHash == key.artifactHash)
    #expect(miss.pageBucket == key.pageBucket)
    #expect(miss.deviceID == key.deviceID)
    #expect(miss.inputDType == key.inputDType)
    #expect(miss.runtimeProfile == key.runtimeProfile)
    #expect(miss.layoutSignature == key.layoutSignature)
    #expect(miss.runtimeMetadata == nil)
    #expect(miss.failureReason == nil)

    let failure = try decode(records[1])
    #expect(failure.traceID == "trace-failure")
    #expect(failure.event == "fallback-kernel-cache-create-failure")
    #expect(failure.artifactHash == key.artifactHash)
    #expect(failure.pageBucket == key.pageBucket)
    #expect(failure.deviceID == key.deviceID)
    #expect(failure.inputDType == key.inputDType)
    #expect(failure.runtimeProfile == key.runtimeProfile)
    #expect(failure.layoutSignature == key.layoutSignature)
    #expect(failure.failureReason?.contains("creationFailed") == true)
  }

  @Test(.enabled(if: requiresMLXEval))
  func fastPathCompiledGraphCacheReusesPerBucketEntry() throws {
    TensorLexer.resetFastPathGraphCache()
    let runtime = try makeLiteralRuntime()
    let bytes = Array("if x".utf8)

    let first = TensorLexer.lexPage(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v0)
    )
    let second = TensorLexer.lexPage(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v0)
    )

    #expect(first == second)

    let metrics = TensorLexer.fastPathGraphMetrics()
    #expect(metrics.compileCount == 1)
    #expect(metrics.cacheMisses == 1)
    #expect(metrics.cacheHits >= 1)

    let store = try #require(
      metrics.cacheEvents.first { $0.event == "fast-path-graph-cache-store" })
    #expect(store.pageBucket == 4096)
    #expect(store.runtimeMetadata?.pipelineFunction == "fastPathPageGraph")
  }
}

private final class LogSink: @unchecked Sendable {
  private let lock = NSLock()
  private var records: [String] = []

  func record(_ message: String) {
    lock.lock()
    records.append(message)
    lock.unlock()
  }

  func snapshot() -> [String] {
    lock.lock()
    let copy = records
    lock.unlock()
    return copy
  }
}

private func decode(_ raw: String) throws -> KernelCacheLog {
  let decoder = JSONDecoder()
  return try decoder.decode(KernelCacheLog.self, from: Data(raw.utf8))
}

private func makeKey(pageBucket: Int, inputDType: String) -> KernelCacheKey {
  KernelCacheKey(
    deviceID: "metal-apple-m4",
    artifactHash: "abc123def",
    pageBucket: pageBucket,
    inputDType: inputDType,
    runtimeProfile: "v1-fallback",
    layoutSignature: "v1"
  )
}

private func makeRuntimeMetadata(deviceID: String) -> KernelCacheRuntimeMetadata {
  KernelCacheRuntimeMetadata(
    backend: "mlx",
    deviceID: deviceID,
    pipelineFunction: "fastPathPageGraph",
    constantTableByteCount: 128,
    fallbackRuleCount: 1,
    stepStride: 2,
    maxClassCount: 64
  )
}

private func makeLiteralRuntime() throws -> ArtifactRuntime {
  var byteToClass = Array(repeating: UInt8(1), count: 256)
  byteToClass[Int(Character("i").asciiValue!)] = 0
  byteToClass[Int(Character("f").asciiValue!)] = 2

  let literalRule = LoweredRule(
    ruleID: 1,
    name: "kw-if",
    tokenKindID: 7,
    mode: .emit,
    family: .literal,
    priorityRank: 0,
    minWidth: 2,
    maxWidth: 2,
    firstClassSetID: 0,
    plan: .literal(bytes: Array("if".utf8))
  )

  let identRule = LoweredRule(
    ruleID: 2,
    name: "ident",
    tokenKindID: 8,
    mode: .emit,
    family: .run,
    priorityRank: 1,
    minWidth: 1,
    maxWidth: nil,
    firstClassSetID: 1,
    plan: .runClassRun(bodyClassSetID: 1, minLength: 1)
  )

  let artifact = LexerArtifact(
    formatVersion: 1,
    specName: "kernel-cache-fast-path-tests",
    specHashHex: String(repeating: "0", count: 64),
    generatorVersion: "tests",
    runtimeHints: RuntimeHints(
      maxLiteralLength: 2,
      maxBoundedRuleWidth: 2,
      maxDeterministicLookaheadBytes: 2
    ),
    tokenKinds: [
      TokenKindDecl(tokenKindID: 7, name: "kwIf", defaultMode: .emit),
      TokenKindDecl(tokenKindID: 8, name: "ident", defaultMode: .emit),
    ],
    byteToClass: byteToClass,
    classes: [
      ByteClassDecl(classID: 0, bytes: [Character("i").asciiValue!]),
      ByteClassDecl(classID: 1, bytes: [Character(" ").asciiValue!]),
      ByteClassDecl(classID: 2, bytes: [Character("f").asciiValue!]),
    ],
    classSets: [ClassSetDecl(classSetID: ClassSetID(1), classes: [0, 2])],
    rules: [literalRule, identRule],
    keywordRemaps: []
  )

  return try ArtifactRuntime.fromArtifact(artifact)
}
