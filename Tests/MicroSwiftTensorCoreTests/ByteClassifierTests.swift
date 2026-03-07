import Testing

@testable import MicroSwiftTensorCore

@Suite
struct ByteClassifierTests {
  @Test(.enabled(if: requiresMLXEval))
  func classifyMapsBytesThroughLUT() {
    var lut = Array(repeating: UInt16(0), count: 256)
    lut[Int(UInt8(ascii: "a"))] = 10
    lut[Int(UInt8(ascii: "b"))] = 20
    lut[Int(UInt8(ascii: "c"))] = 30

    let bytes: [UInt8] = [UInt8(ascii: "a"), UInt8(ascii: "c"), UInt8(ascii: "b")]

    let classIDs = ByteClassifier.classify(bytes: bytes, byteToClassLUT: lut)

    #expect(classIDs == [10, 30, 20])
  }

  @Test(.enabled(if: requiresMLXEval))
  func validityMaskHonorsBoundary() {
    let mask = ByteClassifier.validityMask(pageSize: 6, validLen: 4)

    #expect(mask == [true, true, true, true, false, false])
  }
}
