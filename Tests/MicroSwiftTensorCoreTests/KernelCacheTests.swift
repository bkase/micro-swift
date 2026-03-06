import Foundation
import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct KernelCacheTests {
  @Test
  func cacheMissThenHit() throws {
    let sink = LogSink()
    let cache = KernelCache(logSink: sink.record)
    let key = makeKey(pageBucket: 128, inputDType: "uint16")
    let runner = FallbackKernelRunner(fallback: makeFallbackRuntime())
    let metadata = makeRuntimeMetadata(deviceID: key.deviceID)

    let firstLookup = cache.lookup(key: key, traceID: "trace-miss")
    #expect(firstLookup == nil)

    cache.store(
      key: key,
      entry: KernelCacheEntry(
        fallbackRunner: runner,
        runtimeMetadata: metadata,
        createdAt: Date(timeIntervalSince1970: 10)
      ),
      traceID: "trace-store"
    )

    let secondLookup = cache.lookup(key: key, traceID: "trace-hit")
    let entry = try #require(secondLookup)
    #expect(entry.fallbackRunner.fallback.maxWidth == runner.fallback.maxWidth)
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

  @Test
  func differentKeysReturnDifferentEntries() throws {
    let cache = KernelCache()
    let keyA = makeKey(pageBucket: 64, inputDType: "uint16")
    let keyB = makeKey(pageBucket: 128, inputDType: "float16")

    let runnerA = FallbackKernelRunner(fallback: makeFallbackRuntime(maxWidth: 3))
    let runnerB = FallbackKernelRunner(fallback: makeFallbackRuntime(maxWidth: 7))

    cache.store(
      key: keyA,
      entry: KernelCacheEntry(
        fallbackRunner: runnerA,
        runtimeMetadata: makeRuntimeMetadata(deviceID: keyA.deviceID),
        createdAt: Date(timeIntervalSince1970: 100)
      )
    )
    cache.store(
      key: keyB,
      entry: KernelCacheEntry(
        fallbackRunner: runnerB,
        runtimeMetadata: makeRuntimeMetadata(deviceID: keyB.deviceID),
        createdAt: Date(timeIntervalSince1970: 200)
      )
    )

    let entryA = try #require(cache.lookup(key: keyA, traceID: "trace-a"))
    let entryB = try #require(cache.lookup(key: keyB, traceID: "trace-b"))

    #expect(entryA.fallbackRunner.fallback.maxWidth == 3)
    #expect(entryB.fallbackRunner.fallback.maxWidth == 7)
    #expect(entryA.createdAt != entryB.createdAt)
    #expect(entryA.runtimeMetadata.deviceID == keyA.deviceID)
    #expect(entryB.runtimeMetadata.deviceID == keyB.deviceID)
  }

  @Test
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
    #expect(miss.runtimeMetadata == nil)
    #expect(miss.failureReason == nil)

    let failure = try decode(records[1])
    #expect(failure.traceID == "trace-failure")
    #expect(failure.event == "fallback-kernel-cache-create-failure")
    #expect(failure.artifactHash == key.artifactHash)
    #expect(failure.pageBucket == key.pageBucket)
    #expect(failure.deviceID == key.deviceID)
    #expect(failure.inputDType == key.inputDType)
    #expect(failure.failureReason?.contains("creationFailed") == true)
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
    inputDType: inputDType
  )
}

private func makeFallbackRuntime(maxWidth: UInt16 = 5) -> FallbackRuntime {
  FallbackRuntime(
    numStatesUsed: 2,
    maxWidth: maxWidth,
    startMaskLo: 0,
    startMaskHi: 0,
    stepLo: [],
    stepHi: [],
    acceptLoByRule: [],
    acceptHiByRule: [],
    globalRuleIDByFallbackRule: [],
    priorityRankByFallbackRule: [],
    tokenKindIDByFallbackRule: [],
    modeByFallbackRule: [],
    startClassMaskLo: 0,
    startClassMaskHi: 0
  )
}

private func makeRuntimeMetadata(deviceID: String) -> KernelCacheRuntimeMetadata {
  KernelCacheRuntimeMetadata(
    backend: "metal",
    deviceID: deviceID,
    pipelineFunction: "fallbackKernel",
    constantTableByteCount: 128,
    fallbackRuleCount: 1,
    stepStride: 2,
    maxClassCount: 64
  )
}
