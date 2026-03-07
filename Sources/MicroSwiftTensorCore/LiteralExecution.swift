import MLX
import MicroSwiftLexerGen

public enum LiteralExecution {
  public struct TensorBucketCandidate {
    public let ruleIndex: Int
    public let candLenTensor: MLXArray

    public init(ruleIndex: Int, candLenTensor: MLXArray) {
      self.ruleIndex = ruleIndex
      self.candLenTensor = candLenTensor
    }
  }

  /// Device-oriented literal evaluation over a compiled page.
  /// For literal bytes [b0, b1, ..., bL-1]:
  ///   startMask[i] = validMask[i..i+L-1] && bytes[i+k] == bk for all k
  ///   candLen[i] = L if startMask[i] else 0
  public static func evaluateLiteral(
    compiledPage: CompiledPageInput,
    literalBytes: [UInt8]
  ) -> MLXArray {
    evaluateLiteral(
      byteTensor: compiledPage.shiftedByteTensor(by: 0),
      validMaskTensor: compiledPage.validRangeMask(dtype: .bool),
      pageLen: compiledPage.byteCapacity,
      literalBytes: literalBytes,
      shiftedBytes: { offset in
        compiledPage.shiftedByteTensor(by: offset)
      },
      shiftedMask: { offset in
        compiledPage.shiftedValidMaskTensor(by: offset)
      }
    )
  }

  /// Evaluate all literal rules in a bucket (same length), returns [R, P] candidate lengths as tensors.
  public static func evaluateLiteralBucket(
    compiledPage: CompiledPageInput,
    rules: [(ruleIndex: Int, literalBytes: [UInt8])]
  ) -> [TensorBucketCandidate] {
    rules.map { rule in
      TensorBucketCandidate(
        ruleIndex: rule.ruleIndex,
        candLenTensor: evaluateLiteral(compiledPage: compiledPage, literalBytes: rule.literalBytes)
      )
    }
  }

  /// Compatibility host wrapper used by non-device test harnesses.
  public static func evaluateLiteral(
    bytes: [UInt8],
    validMask: [Bool],
    literalBytes: [UInt8]
  ) -> [UInt16] {
    let pageLen = min(bytes.count, validMask.count)
    guard pageLen > 0 else { return [] }

    let bytesTensor = withMLXCPU {
      MLXArray(Array(bytes.prefix(pageLen)), [pageLen]).asType(.uint8)
    }
    let validMaskTensor = withMLXCPU {
      MLXArray(Array(validMask.prefix(pageLen)), [pageLen]).asType(.bool)
    }
    let candLen = evaluateLiteral(
      byteTensor: bytesTensor,
      validMaskTensor: validMaskTensor,
      pageLen: pageLen,
      literalBytes: literalBytes,
      shiftedBytes: { offset in
        ShiftedTensorView.forward(bytesTensor, by: offset)
      },
      shiftedMask: { offset in
        ShiftedTensorView.forwardValidMask(validMaskTensor, by: offset)
      }
    )
    return candLen.asArray(UInt16.self)
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

  private static func evaluateLiteral(
    byteTensor: MLXArray,
    validMaskTensor: MLXArray,
    pageLen: Int,
    literalBytes: [UInt8],
    shiftedBytes: (Int) -> MLXArray,
    shiftedMask: (Int) -> MLXArray
  ) -> MLXArray {
    withMLXCPU {
      guard pageLen > 0 else { return zeros([0], dtype: .uint16) }

      let literalLen = literalBytes.count
      guard literalLen > 0, literalLen <= pageLen else {
        return zeros([pageLen], dtype: .uint16)
      }

      var startMask = validMaskTensor

      for offset in 0..<literalLen {
        let shiftedBytesTensor = shiftedBytes(offset)
        let shiftedValidMask = shiftedMask(offset)
        let byteMatch = shiftedBytesTensor .== literalBytes[offset]
        startMask = startMask .&& shiftedValidMask .&& byteMatch
      }

      let literalLenU16 = UInt16(min(literalLen, Int(UInt16.max)))
      return which(startMask, Int32(literalLenU16), 0).asType(.uint16)
    }
  }
}
