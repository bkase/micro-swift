import Foundation

/// Shared edge-case fixtures for newline/EOF testing across M1.
/// Each fixture is a named byte array with a description of the edge case it covers.
enum SourceFixtures {
  struct Fixture {
    let name: String
    let bytes: Data
    /// Expected line start offsets (Int64) per the M1 newline contract.
    let expectedLineStartOffsets: [Int64]
  }

  static let empty = Fixture(
    name: "empty",
    bytes: Data(),
    expectedLineStartOffsets: [0]
  )

  static let singleByte = Fixture(
    name: "singleByte",
    bytes: Data([0x61]),  // "a"
    expectedLineStartOffsets: [0]
  )

  static let noTrailingNewline = Fixture(
    name: "noTrailingNewline",
    bytes: Data([0x61, 0x62, 0x63]),  // "abc"
    expectedLineStartOffsets: [0]
  )

  static let trailingLF = Fixture(
    name: "trailingLF",
    bytes: Data([0x61, 0x0A]),  // "a\n"
    expectedLineStartOffsets: [0, 2]
  )

  static let trailingCRLF = Fixture(
    name: "trailingCRLF",
    bytes: Data([0x61, 0x0D, 0x0A]),  // "a\r\n"
    expectedLineStartOffsets: [0, 3]
  )

  static let multipleBlanksLF = Fixture(
    name: "multipleBlanksLF",
    bytes: Data([0x0A, 0x0A, 0x0A]),  // "\n\n\n"
    expectedLineStartOffsets: [0, 1, 2, 3]
  )

  static let lfOnly = Fixture(
    name: "lfOnly",
    bytes: Data([0x61, 0x0A, 0x62, 0x0A, 0x63]),  // "a\nb\nc"
    expectedLineStartOffsets: [0, 2, 4]
  )

  static let crlfOnly = Fixture(
    name: "crlfOnly",
    bytes: Data([0x61, 0x0D, 0x0A, 0x62]),  // "a\r\nb"
    expectedLineStartOffsets: [0, 3]
  )

  static let loneCR = Fixture(
    name: "loneCR",
    bytes: Data([0x61, 0x0D, 0x62]),  // "a\rb"
    expectedLineStartOffsets: [0, 2]
  )

  static let crFollowedByLF = Fixture(
    name: "crFollowedByLF (CRLF is single break)",
    bytes: Data([0x61, 0x0D, 0x0A, 0x62]),  // "a\r\nb"
    expectedLineStartOffsets: [0, 3]
  )

  static let mixedLineEndings = Fixture(
    name: "mixedLineEndings",
    // "a\nb\r\nc\rd"
    bytes: Data([0x61, 0x0A, 0x62, 0x0D, 0x0A, 0x63, 0x0D, 0x64]),
    expectedLineStartOffsets: [0, 2, 5, 7]
  )

  static let nullBytes = Fixture(
    name: "nullBytes",
    bytes: Data([0x00, 0x0A, 0x00]),  // "\0\n\0"
    expectedLineStartOffsets: [0, 2]
  )

  static let nonASCIIUTF8 = Fixture(
    name: "nonASCIIUTF8",
    // "é\n" = [0xC3, 0xA9, 0x0A]
    bytes: Data([0xC3, 0xA9, 0x0A]),
    expectedLineStartOffsets: [0, 3]
  )

  static let longFinalLineNoNewline = Fixture(
    name: "longFinalLineNoNewline",
    bytes: Data([0x61, 0x0A] + Array(repeating: UInt8(0x62), count: 200)),
    expectedLineStartOffsets: [0, 2]
  )

  /// All fixtures in a stable order for iteration.
  static let all: [Fixture] = [
    empty, singleByte, noTrailingNewline, trailingLF, trailingCRLF,
    multipleBlanksLF, lfOnly, crlfOnly, loneCR, crFollowedByLF,
    mixedLineEndings, nullBytes, nonASCIIUTF8, longFinalLineNoNewline,
  ]
}
