import Foundation
import Testing

@testable import MicroSwiftFrontend

// MARK: - Scalar oracle (reference implementation in tests only)

private enum ScalarOracle {
  static func lineTerminatorEndMask(bytes: [UInt8]) -> [Bool] {
    let n = bytes.count
    guard n > 0 else { return [] }
    var mask = [Bool](repeating: false, count: n)
    for i in 0..<n {
      let isLF = bytes[i] == 0x0A
      let isCR = bytes[i] == 0x0D
      let nextIsLF = (i + 1 < n) && (bytes[i + 1] == 0x0A)
      mask[i] = isLF || (isCR && !nextIsLF)
    }
    return mask
  }

  static func lineStartOffsets(bytes: [UInt8]) -> [Int64] {
    let mask = lineTerminatorEndMask(bytes: bytes)
    var offsets: [Int64] = [0]
    for (i, isEnd) in mask.enumerated() where isEnd {
      offsets.append(Int64(i + 1))
    }
    return offsets
  }

  static func resolve(_ offset: Int64, lineStartOffsets: [Int64]) -> (line: Int, column: Int) {
    var lo = 0
    var hi = lineStartOffsets.count
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if lineStartOffsets[mid] <= offset {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    let line = lo - 1
    let column = Int(offset - lineStartOffsets[line])
    return (line, column)
  }
}

// MARK: - Line terminator mask tests

@Suite
struct LineTerminatorMaskTests {
  @Test func emptyFile() {
    let mask = LineStructure.lineTerminatorEndMask(bytes: Data())
    #expect(mask.isEmpty)
  }

  @Test func lfMarksAtLF() {
    // "a\nb"
    let mask = LineStructure.lineTerminatorEndMask(bytes: Data([0x61, 0x0A, 0x62]))
    #expect(mask == [false, true, false])
  }

  @Test func crlfMarksAtLFOnly() {
    // "a\r\nb"
    let mask = LineStructure.lineTerminatorEndMask(bytes: Data([0x61, 0x0D, 0x0A, 0x62]))
    #expect(mask == [false, false, true, false])
  }

  @Test func loneCRMarksAtCR() {
    // "a\rb"
    let mask = LineStructure.lineTerminatorEndMask(bytes: Data([0x61, 0x0D, 0x62]))
    #expect(mask == [false, true, false])
  }
}

// MARK: - Line start offsets tests

@Suite
struct LineStartOffsetsTests {
  @Test func allFixturesMatchExpected() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      #expect(
        offsets == fixture.expectedLineStartOffsets,
        "Fixture \(fixture.name): got \(offsets), expected \(fixture.expectedLineStartOffsets)"
      )
    }
  }

  @Test func startsWithZero() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      #expect(offsets.first == 0, "Fixture \(fixture.name): must start with 0")
    }
  }

  @Test func strictlyIncreasing() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      for i in 1..<offsets.count {
        #expect(offsets[i] > offsets[i - 1], "Fixture \(fixture.name): not strictly increasing at \(i)")
      }
    }
  }

  @Test func allOffsetsInBounds() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      for o in offsets {
        #expect(o >= 0 && o <= Int64(fixture.bytes.count), "Fixture \(fixture.name): offset \(o) out of bounds")
      }
    }
  }
}

// MARK: - Scalar oracle parity tests

@Suite
struct OracleParityTests {
  @Test func maskParityOnAllFixtures() {
    for fixture in SourceFixtures.all {
      let production = LineStructure.lineTerminatorEndMask(bytes: fixture.bytes)
      let oracle = ScalarOracle.lineTerminatorEndMask(bytes: Array(fixture.bytes))
      #expect(production == oracle, "Mask parity failed for \(fixture.name)")
    }
  }

  @Test func offsetsParityOnAllFixtures() {
    for fixture in SourceFixtures.all {
      let production = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      let oracle = ScalarOracle.lineStartOffsets(bytes: Array(fixture.bytes))
      #expect(production == oracle, "Offsets parity failed for \(fixture.name)")
    }
  }

  @Test func lineCountEqualsOnesPlusTerminators() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      let mask = LineStructure.lineTerminatorEndMask(bytes: fixture.bytes)
      let terminatorCount = mask.filter { $0 }.count
      #expect(offsets.count == 1 + terminatorCount, "Fixture \(fixture.name): lineCount invariant")
    }
  }
}

// MARK: - HostLineIndex tests

@Suite
struct HostLineIndexTests {
  @Test func lineCountMatchesOffsetCount() {
    for fixture in SourceFixtures.all {
      let idx = LineStructure.hostLineIndex(bytes: fixture.bytes)
      #expect(idx.lineCount == Int32(idx.lineStartOffsets.count), "Fixture \(fixture.name)")
    }
  }
}

// MARK: - Location resolver tests

@Suite
struct SourceResolverTests {
  let fid = FileID(rawValue: 1)

  @Test func resolveStartOfFile() {
    let idx = LineStructure.hostLineIndex(bytes: Data([0x61, 0x0A, 0x62]))  // "a\nb"
    let loc = SourceResolver.resolve(ByteOffset(rawValue: 0), fileID: fid, hostLineIndex: idx)
    #expect(loc.line == LineIndex(rawValue: 0))
    #expect(loc.column == ColumnIndex(rawValue: 0))
  }

  @Test func resolveSecondLine() {
    // "a\nb"
    let idx = LineStructure.hostLineIndex(bytes: Data([0x61, 0x0A, 0x62]))
    let loc = SourceResolver.resolve(ByteOffset(rawValue: 2), fileID: fid, hostLineIndex: idx)
    #expect(loc.line == LineIndex(rawValue: 1))
    #expect(loc.column == ColumnIndex(rawValue: 0))
  }

  @Test func resolveEOF() {
    // "a\nb" — byteCount=3, EOF offset=3
    let idx = LineStructure.hostLineIndex(bytes: Data([0x61, 0x0A, 0x62]))
    let loc = SourceResolver.resolve(ByteOffset(rawValue: 3), fileID: fid, hostLineIndex: idx)
    #expect(loc.line == LineIndex(rawValue: 1))
    #expect(loc.column == ColumnIndex(rawValue: 1))
  }

  @Test func resolveEOFWithTrailingNewline() {
    // "a\n" — byteCount=2, EOF at line 1
    let idx = LineStructure.hostLineIndex(bytes: Data([0x61, 0x0A]))
    let loc = SourceResolver.resolve(ByteOffset(rawValue: 2), fileID: fid, hostLineIndex: idx)
    #expect(loc.line == LineIndex(rawValue: 1))
    #expect(loc.column == ColumnIndex(rawValue: 0))
  }

  @Test func resolveEmptyFile() {
    let idx = LineStructure.hostLineIndex(bytes: Data())
    let loc = SourceResolver.resolve(ByteOffset(rawValue: 0), fileID: fid, hostLineIndex: idx)
    #expect(loc.line == LineIndex(rawValue: 0))
    #expect(loc.column == ColumnIndex(rawValue: 0))
  }

  @Test func resolverParityWithOracleOnAllFixtures() {
    for fixture in SourceFixtures.all {
      let idx = LineStructure.hostLineIndex(bytes: fixture.bytes)
      let oracleOffsets = ScalarOracle.lineStartOffsets(bytes: Array(fixture.bytes))
      // Test every byte offset including EOF
      for o in stride(from: Int64(0), through: Int64(fixture.bytes.count), by: 1) {
        let prod = SourceResolver.resolve(ByteOffset(rawValue: o), fileID: fid, hostLineIndex: idx)
        let oracle = ScalarOracle.resolve(o, lineStartOffsets: oracleOffsets)
        #expect(
          prod.line.rawValue == Int32(oracle.line) && prod.column.rawValue == Int32(oracle.column),
          "Fixture \(fixture.name) offset \(o): prod=(\(prod.line.rawValue),\(prod.column.rawValue)) oracle=(\(oracle.line),\(oracle.column))"
        )
      }
    }
  }
}

// MARK: - Property tests with deterministic PRNG

@Suite
struct LineStructurePropertyTests {
  /// Minimal xorshift64 PRNG for deterministic property testing.
  struct Xorshift64 {
    var state: UInt64

    mutating func next() -> UInt64 {
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      return state
    }

    mutating func nextByte() -> UInt8 {
      UInt8(next() & 0xFF)
    }
  }

  @Test func propertyTestRandomCorpora() {
    var rng = Xorshift64(state: 0xDEAD_BEEF_CAFE_BABE)
    for _ in 0..<100 {
      let length = Int(rng.next() % 512)
      var bytes = [UInt8]()
      for _ in 0..<length {
        bytes.append(rng.nextByte())
      }
      let data = Data(bytes)

      let prodOffsets = LineStructure.lineStartOffsets(bytes: data)
      let oracleOffsets = ScalarOracle.lineStartOffsets(bytes: bytes)
      #expect(prodOffsets == oracleOffsets, "Parity failed for random corpus of length \(length)")

      // Invariants
      #expect(prodOffsets.first == 0)
      for i in 1..<prodOffsets.count {
        #expect(prodOffsets[i] > prodOffsets[i - 1])
      }
      for o in prodOffsets {
        #expect(o >= 0 && o <= Int64(length))
      }

      // lineCount == 1 + terminators
      let mask = LineStructure.lineTerminatorEndMask(bytes: data)
      let terminators = mask.filter { $0 }.count
      #expect(prodOffsets.count == 1 + terminators)
    }
  }
}
