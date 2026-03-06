/// A 256-bit set representing membership for each possible byte value (0...255).
public struct ByteSet: Sendable, Equatable, Hashable {
  // Four 64-bit words cover all 256 byte values.
  public var w0: UInt64  // bytes 0...63
  public var w1: UInt64  // bytes 64...127
  public var w2: UInt64  // bytes 128...191
  public var w3: UInt64  // bytes 192...255

  public init(w0: UInt64 = 0, w1: UInt64 = 0, w2: UInt64 = 0, w3: UInt64 = 0) {
    self.w0 = w0
    self.w1 = w1
    self.w2 = w2
    self.w3 = w3
  }

  public static let empty = ByteSet()
  public static let all = ByteSet(w0: .max, w1: .max, w2: .max, w3: .max)

  @inline(__always)
  public func contains(_ byte: UInt8) -> Bool {
    let (wordIndex, bitIndex) = byte.dividing(by: 64)
    switch wordIndex {
    case 0: return w0 & (1 << bitIndex) != 0
    case 1: return w1 & (1 << bitIndex) != 0
    case 2: return w2 & (1 << bitIndex) != 0
    case 3: return w3 & (1 << bitIndex) != 0
    default: return false
    }
  }

  @inline(__always)
  public mutating func insert(_ byte: UInt8) {
    let (wordIndex, bitIndex) = byte.dividing(by: 64)
    let mask: UInt64 = 1 << bitIndex
    switch wordIndex {
    case 0: w0 |= mask
    case 1: w1 |= mask
    case 2: w2 |= mask
    case 3: w3 |= mask
    default: break
    }
  }

  public init(bytes: some Sequence<UInt8>) {
    self = .empty
    for b in bytes { insert(b) }
  }

  public init(range: ClosedRange<UInt8>) {
    self.init(bytes: range)
  }

  public var complement: ByteSet {
    ByteSet(w0: ~w0, w1: ~w1, w2: ~w2, w3: ~w3)
  }

  public func union(_ other: ByteSet) -> ByteSet {
    ByteSet(w0: w0 | other.w0, w1: w1 | other.w1, w2: w2 | other.w2, w3: w3 | other.w3)
  }

  public func intersection(_ other: ByteSet) -> ByteSet {
    ByteSet(w0: w0 & other.w0, w1: w1 & other.w1, w2: w2 & other.w2, w3: w3 & other.w3)
  }

  public var isEmpty: Bool {
    w0 == 0 && w1 == 0 && w2 == 0 && w3 == 0
  }

  public var count: Int {
    w0.nonzeroBitCount + w1.nonzeroBitCount + w2.nonzeroBitCount + w3.nonzeroBitCount
  }

  /// Returns all member bytes in ascending order.
  public var members: [UInt8] {
    var result: [UInt8] = []
    result.reserveCapacity(count)
    for b in UInt8.min...UInt8.max {
      if contains(b) { result.append(b) }
    }
    return result
  }
}

// MARK: - Predefined byte sets

extension ByteSet {
  public static let asciiDigit = ByteSet(range: UInt8(ascii: "0")...UInt8(ascii: "9"))

  public static let asciiLower = ByteSet(range: UInt8(ascii: "a")...UInt8(ascii: "z"))
  public static let asciiUpper = ByteSet(range: UInt8(ascii: "A")...UInt8(ascii: "Z"))
  public static let asciiLetter = asciiLower.union(.asciiUpper)

  public static let underscore = ByteSet(bytes: [UInt8(ascii: "_")])

  public static let asciiIdentStart = asciiLetter.union(.underscore)
  public static let asciiIdentContinue = asciiIdentStart.union(.asciiDigit)

  public static let newline = ByteSet(bytes: [UInt8(ascii: "\n")])
  public static let carriageReturn = ByteSet(bytes: [UInt8(ascii: "\r")])
  public static let newlines = newline.union(.carriageReturn)

  public static let space = ByteSet(bytes: [UInt8(ascii: " ")])
  public static let tab = ByteSet(bytes: [UInt8(ascii: "\t")])
  public static let asciiWhitespace = space.union(.tab).union(.newlines)
}

// MARK: - Codable

extension ByteSet: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let bytes = try container.decode([UInt8].self)
    self.init(bytes: bytes)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(members)
  }
}

// MARK: - Helpers

extension UInt8 {
  fileprivate func dividing(by divisor: UInt8) -> (quotient: UInt8, remainder: UInt8) {
    (self / divisor, self % divisor)
  }
}
