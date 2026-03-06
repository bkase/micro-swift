public enum ByteClassifier {
  /// Classify each byte to its class ID using the byteToClass LUT.
  /// Input: raw bytes [P], Output: classIDs [P]
  public static func classify(bytes: [UInt8], byteToClassLUT: [UInt8]) -> [UInt8] {
    bytes.map { byteToClassLUT[Int($0)] }
  }

  /// Build validity mask: validMask[i] = (i < validLen)
  public static func validityMask(pageSize: Int, validLen: Int32) -> [Bool] {
    (0..<pageSize).map { $0 < Int(validLen) }
  }
}
