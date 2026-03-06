import Testing
@testable import MicroSwiftTensorCore

@Suite
struct PackedTokenTests {
  @Test
  func packUnpackRoundTrip() {
    let localStart: UInt16 = 0x1234
    let length: UInt16 = 0x00FF
    let tokenKindID: UInt16 = 0xBEEF
    let flags: UInt8 = 0xA5

    let packed = PackedToken.pack(
      localStart: localStart,
      length: length,
      tokenKindID: tokenKindID,
      flags: flags
    )

    #expect(PackedToken.unpackLocalStart(packed) == localStart)
    #expect(PackedToken.unpackLength(packed) == length)
    #expect(PackedToken.unpackTokenKindID(packed) == tokenKindID)
    #expect(PackedToken.unpackFlags(packed) == flags)
  }
}
