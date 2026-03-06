struct FallbackBuildError: Error, Sendable, Equatable {
  let message: String
}

extension ValidatedSpec {
  func buildFallbackPlan(
    regex: NormalizedRegex,
    byteClasses: ByteClasses,
    options: CompileOptions
  ) throws -> FallbackPlan {
    let classCount = byteClasses.classes.count
    guard classCount > 0 else {
      throw FallbackBuildError(message: "Cannot build fallback DFA with zero byte classes.")
    }

    let dead = NormalizedRegex.never
    let start = regex
    var states: [NormalizedRegex] = [dead, start]
    var queue = [1]

    var idsByKey: [String: Int] = [
      dead.canonicalKey: 0,
      start.canonicalKey: 1,
    ]

    var transitions = Array(repeating: UInt32(0), count: classCount)

    while !queue.isEmpty {
      let stateID = queue.removeFirst()
      let stateRegex = states[stateID]

      for classID in 0..<classCount {
        let representative = byteClasses.classes[classID].bytes[0]
        let nextRegex = stateRegex.derivative(by: representative)
        let nextID: Int

        if nextRegex == .never {
          nextID = 0
        } else if let existing = idsByKey[nextRegex.canonicalKey] {
          nextID = existing
        } else {
          nextID = states.count
          guard nextID <= options.maxFallbackStatesPerRule else {
            throw FallbackBuildError(
              message:
                "Fallback states exceeded maxFallbackStatesPerRule=\(options.maxFallbackStatesPerRule)."
            )
          }
          states.append(nextRegex)
          idsByKey[nextRegex.canonicalKey] = nextID
          queue.append(nextID)
        }

        transitions.append(UInt32(nextID))
      }
    }

    let accepting = states.enumerated().compactMap { idx, state in
      state.props.nullable ? UInt32(idx) : nil
    }

    return FallbackPlan(
      stateCount: UInt32(states.count),
      classCount: UInt16(classCount),
      transitionRowStride: UInt16(classCount),
      startState: 1,
      acceptingStates: accepting,
      transitions: transitions
    )
  }
}

extension NormalizedRegex {
  fileprivate func derivative(by byte: UInt8) -> NormalizedRegex {
    switch self {
    case .never, .epsilon:
      return .never

    case .literal(let bytes):
      guard let first = bytes.first, first == byte else { return .never }
      let rest = Array(bytes.dropFirst())
      return rest.isEmpty ? .epsilon : .literal(rest)

    case .byteClass(let set):
      return set.contains(byte) ? .epsilon : .never

    case .concat(let children):
      guard let first = children.first else { return .never }
      let tail = Array(children.dropFirst())
      var branches: [NormalizedRegex] = []

      let firstDerived = first.derivative(by: byte)
      if firstDerived != .never {
        branches.append(canonicalize(.concat([firstDerived] + tail)))
      }

      if first.props.nullable {
        let tailRegex: NormalizedRegex = tail.isEmpty ? .epsilon : canonicalize(.concat(tail))
        let tailDerived = tailRegex.derivative(by: byte)
        if tailDerived != .never {
          branches.append(tailDerived)
        }
      }

      return canonicalize(.alt(branches))

    case .alt(let children):
      let branches = children.map { $0.derivative(by: byte) }.filter { $0 != .never }
      return canonicalize(.alt(branches))

    case .repetition(let child, let min, let max):
      guard max != 0 else { return .never }
      let nextMin = Swift.max(min - 1, 0)
      let nextMax = max.map { $0 - 1 }
      let tail = canonicalize(.repetition(child, min: nextMin, max: nextMax))
      return canonicalize(.concat([child.derivative(by: byte), tail]))
    }
  }
}

private func canonicalize(_ regex: NormalizedRegex) -> NormalizedRegex {
  NormalizedRegex.normalize(raw(from: regex))
}

private func raw(from regex: NormalizedRegex) -> RawRegex {
  switch regex {
  case .never:
    return .byteClass(.empty)
  case .epsilon:
    return .literal([])
  case .literal(let bytes):
    return .literal(bytes)
  case .byteClass(let set):
    return .byteClass(set)
  case .concat(let children):
    return .concat(children.map(raw(from:)))
  case .alt(let children):
    return .alt(children.map(raw(from:)))
  case .repetition(let child, let min, let max):
    return .repetition(raw(from: child), min: min, max: max)
  }
}
