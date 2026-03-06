public func greedyNonOverlapSelect(
  winners: [CandidateWinner],
  validLen: Int
) -> [CandidateWinner] {
  guard validLen > 0 else { return [] }

  let bestByPosition = reduceBucketWinners(buckets: [winners])
  var selected: [CandidateWinner] = []
  var coveredUntil = 0

  for position in 0..<validLen {
    let winner =
      position < bestByPosition.count
      ? bestByPosition[position] : CandidateWinner.noMatch(at: position)
    if winner.len > 0, position >= coveredUntil {
      selected.append(winner)
      coveredUntil = position + Int(winner.len)
    }
  }

  return selected
}
