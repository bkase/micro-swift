import MicroSwiftLexerGen

public enum LiteralExecution {
  /// Evaluate a single literal rule over the page.
  /// For literal bytes [b0, b1, ..., bL-1]:
  ///   startMask[i] = validMask[i..i+L-1] && bytes[i+k] == bk for all k
  ///   candLen[i] = L if startMask[i] else 0
  public static func evaluateLiteral(
    bytes: [UInt8],
    validMask: [Bool],
    literalBytes: [UInt8]
  ) -> [UInt16] {
    let pageLen = min(bytes.count, validMask.count)
    var candLen = Array(repeating: UInt16(0), count: pageLen)

    let literalLen = literalBytes.count
    guard pageLen > 0, literalLen > 0, literalLen <= pageLen else {
      return candLen
    }

    for start in 0...(pageLen - literalLen) {
      var matches = true
      for offset in 0..<literalLen {
        let index = start + offset
        if !validMask[index] || bytes[index] != literalBytes[offset] {
          matches = false
          break
        }
      }

      if matches {
        candLen[start] = UInt16(literalLen)
      }
    }

    return candLen
  }

  /// Evaluate all literal rules in a bucket (same length), returns [R, P] candidate lengths.
  public static func evaluateLiteralBucket(
    bytes: [UInt8],
    validMask: [Bool],
    rules: [(ruleIndex: Int, literalBytes: [UInt8])]
  ) -> [[UInt16]] {
    rules.map { rule in
      evaluateLiteral(bytes: bytes, validMask: validMask, literalBytes: rule.literalBytes)
    }
  }
}
