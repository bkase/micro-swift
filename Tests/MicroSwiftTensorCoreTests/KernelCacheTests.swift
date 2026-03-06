import Foundation
import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct KernelCacheTests {
  @Test
  func cacheMissThenHit() async throws {
    let sink = LogSink()
    let cache = KernelCache(logSink: sink.record)
    let key = makeKey(pageBucket: 128, inputDType: "uint16")
    let runner = FallbackKernelRunner(fallback: makeFallbackRuntime())

    let firstLookup = await cache.lookup(key: key, traceID: "trace-miss")
    #expect(firstLookup == nil)

    await cache.store(
      key: key,
      entry: KernelCacheEntry(fallbackRunner: runner, createdAt: Date(timeIntervalSince1970: 10))
    )

    let secondLookup = await cache.lookup(key: key, traceID: "trace-hit")
    let entry = try #require(secondLookup)
    #expect(entry.fallbackRunner.fallback.maxWidth == runner.fallback.maxWidth)

    let records = sink.snapshot()
    #expect(records.count == 1)

    let miss = try decode(records[0])
    #expect(miss.traceID == "trace-miss")
    #expect(miss.event == "fallback-kernel-cache-miss")
    #expect(miss.artifactHash == key.artifactHash)
    #expect(miss.pageBucket == key.pageBucket)
    #expect(miss.deviceID == key.deviceID)
    #expect(miss.failureReason == nil)
  }

  @Test
  func differentKeysReturnDifferentEntries() async throws {
    let cache = KernelCache()
    let keyA = makeKey(pageBucket: 64, inputDType: "uint16")
    let keyB = makeKey(pageBucket: 128, inputDType: "float16")

    let runnerA = FallbackKernelRunner(fallback: makeFallbackRuntime(maxWidth: 3))
    let runnerB = FallbackKernelRunner(fallback: makeFallbackRuntime(maxWidth: 7))

    await cache.store(
      key: keyA,
      entry: KernelCacheEntry(fallbackRunner: runnerA, createdAt: Date(timeIntervalSince1970: 100))
    )
    await cache.store(
      key: keyB,
      entry: KernelCacheEntry(fallbackRunner: runnerB, createdAt: Date(timeIntervalSince1970: 200))
    )

    let entryA = try #require(await cache.lookup(key: keyA, traceID: "trace-a"))
    let entryB = try #require(await cache.lookup(key: keyB, traceID: "trace-b"))

    #expect(entryA.fallbackRunner.fallback.maxWidth == 3)
    #expect(entryB.fallbackRunner.fallback.maxWidth == 7)
    #expect(entryA.createdAt != entryB.createdAt)
  }

  @Test
  func structuredLogOutputFormat() async throws {
    let sink = LogSink()
    let cache = KernelCache(logSink: sink.record)
    let key = makeKey(pageBucket: 256, inputDType: "uint16")

    enum TestError: Error {
      case creationFailed
    }

    await #expect(throws: TestError.creationFailed) {
      _ = try await cache.getOrCreate(key: key, traceID: "trace-failure") {
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
    #expect(miss.failureReason == nil)

    let failure = try decode(records[1])
    #expect(failure.traceID == "trace-failure")
    #expect(failure.event == "fallback-kernel-cache-create-failure")
    #expect(failure.artifactHash == key.artifactHash)
    #expect(failure.pageBucket == key.pageBucket)
    #expect(failure.deviceID == key.deviceID)
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
