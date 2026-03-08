import Testing

@testable import MicroSwiftTensorCore

@Suite
struct NextStopHelperTests {
  @Test(.enabled(if: requiresMLXEval))
  func nextStopFindsCorrectPositions() {
    let stopMask = [false, false, true, false, true, false]

    let nextStop = NextStopHelper.computeNextStop(stopMask: stopMask, validLen: 6)

    #expect(nextStop == [2, 2, 2, 4, 4, 6])
  }

  @Test(.enabled(if: requiresMLXEval))
  func noStopReturnsValidLen() {
    let stopMask = [false, false, false, false]

    let nextStop = NextStopHelper.computeNextStop(stopMask: stopMask, validLen: 4)

    #expect(nextStop == [4, 4, 4, 4])
  }
}
