public enum NextStopHelper {
  /// For each position i, compute the index of the next position >= i where stopMask is true.
  /// If no stop found, returns validLen.
  /// Uses reverse scan (reverse prefix-min equivalent).
  public static func computeNextStop(
    stopMask: [Bool],
    validLen: Int32
  ) -> [Int32] {
    let boundedValidLen = max(Int(validLen), 0)
    let activeCount = min(stopMask.count, boundedValidLen)
    var nextStop = Array(repeating: validLen, count: stopMask.count)
    var nearest = validLen

    if activeCount == 0 {
      return nextStop
    }

    for index in stride(from: activeCount - 1, through: 0, by: -1) {
      if stopMask[index] {
        nearest = Int32(index)
      }
      nextStop[index] = nearest
    }

    return nextStop
  }
}
