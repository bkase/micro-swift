public enum PackedToken {
  private static let localStartMask: UInt64 = 0x0000_0000_0000_FFFF
  private static let lengthMask: UInt64 = 0x0000_0000_FFFF_0000
  private static let tokenKindMask: UInt64 = 0x0000_FFFF_0000_0000
  private static let flagsMask: UInt64 = 0x00FF_0000_0000_0000

  public static func pack(localStart: UInt16, length: UInt16, tokenKindID: UInt16, flags: UInt8)
    -> UInt64
  {
    UInt64(localStart)
      | (UInt64(length) << 16)
      | (UInt64(tokenKindID) << 32)
      | (UInt64(flags) << 48)
  }

  public static func unpackLocalStart(_ packed: UInt64) -> UInt16 {
    UInt16(packed & localStartMask)
  }

  public static func unpackLength(_ packed: UInt64) -> UInt16 {
    UInt16((packed & lengthMask) >> 16)
  }

  public static func unpackTokenKindID(_ packed: UInt64) -> UInt16 {
    UInt16((packed & tokenKindMask) >> 32)
  }

  public static func unpackFlags(_ packed: UInt64) -> UInt8 {
    UInt8((packed & flagsMask) >> 48)
  }
}
