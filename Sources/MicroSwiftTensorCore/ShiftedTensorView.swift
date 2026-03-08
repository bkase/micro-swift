import MLX

enum ShiftedTensorView {
  /// Returns a deterministic forward-shifted 1D view:
  /// output[i] = tensor[i + offset] when in-bounds, else padding value.
  static func forward(
    _ tensor: MLXArray,
    by offset: Int,
    padValue: UInt8 = PageBucket.neutralPaddingByte
  ) -> MLXArray {
    precondition(offset >= 0, "offset must be non-negative")

    let count = Int(tensor.shape[0])
    guard count > 0 else { return tensor }
    guard offset > 0 else { return tensor }

    if offset >= count {
      return zeros([count], dtype: tensor.dtype)
    }

    precondition(
      padValue == PageBucket.neutralPaddingByte,
      "only neutral padding is supported"
    )

    let shiftedCore = tensor[offset..<count]
    let tailPadding = zeros([offset], dtype: tensor.dtype)
    return concatenated([shiftedCore, tailPadding], axis: 0)
  }

  static func forwardValidMask(_ mask: MLXArray, by offset: Int) -> MLXArray {
    precondition(offset >= 0, "offset must be non-negative")

    let count = Int(mask.shape[0])
    guard count > 0 else { return mask }
    guard offset > 0 else { return mask }

    if offset >= count {
      return zeros([count], dtype: .bool)
    }

    let shiftedCore = mask[offset..<count]
    let tailPadding = zeros([offset], dtype: .bool)
    return concatenated([shiftedCore, tailPadding], axis: 0)
  }
}
