/// The raw regex AST produced by the DSL constructors.
/// This is the user-facing representation before normalization.
public indirect enum RawRegex: Sendable, Equatable, Hashable {
  /// Match a fixed byte string.
  case literal([UInt8])
  /// Match any single byte in the set.
  case byteClass(ByteSet)
  /// Concatenation of sub-patterns.
  case concat([RawRegex])
  /// Alternation (union) of sub-patterns.
  case alt([RawRegex])
  /// Bounded or unbounded repetition.
  case repetition(RawRegex, min: Int, max: Int?)  // nil max = unbounded
}

// MARK: - DSL convenience constructors

extension RawRegex {
  /// A single ASCII byte literal.
  public static func byte(_ b: UInt8) -> RawRegex {
    .literal([b])
  }
}

// MARK: - Operator-style concatenation

infix operator <> : AdditionPrecedence

/// Concatenation operator for the regex DSL.
public func <> (lhs: RawRegex, rhs: RawRegex) -> RawRegex {
  // Flatten nested concats at construction time for ergonomics
  var children: [RawRegex] = []
  if case .concat(let l) = lhs { children.append(contentsOf: l) } else { children.append(lhs) }
  if case .concat(let r) = rhs { children.append(contentsOf: r) } else { children.append(rhs) }
  return .concat(children)
}

// MARK: - DSL free functions

/// Match a fixed ASCII string as a literal byte sequence.
/// Traps if the string contains non-ASCII characters.
public func literal(_ s: String) -> RawRegex {
  precondition(s.allSatisfy(\.isASCII), "literal() requires ASCII-only strings")
  return .literal(Array(s.utf8))
}

/// Match one or more occurrences.
public func oneOrMore(_ r: RawRegex) -> RawRegex {
  .repetition(r, min: 1, max: nil)
}

/// Match zero or more occurrences.
public func zeroOrMore(_ r: RawRegex) -> RawRegex {
  .repetition(r, min: 0, max: nil)
}

/// Match zero or one occurrence.
public func optional(_ r: RawRegex) -> RawRegex {
  .repetition(r, min: 0, max: 1)
}

/// Bounded repetition.
public func repeated(_ r: RawRegex, exactly n: Int) -> RawRegex {
  .repetition(r, min: n, max: n)
}

/// Bounded repetition with range.
public func repeated(_ r: RawRegex, min: Int, max: Int) -> RawRegex {
  .repetition(r, min: min, max: max)
}

/// Unbounded repetition with minimum.
public func repeated(_ r: RawRegex, atLeast n: Int) -> RawRegex {
  .repetition(r, min: n, max: nil)
}

/// Complement a byte class.
public func not(_ bs: ByteSet) -> RawRegex {
  .byteClass(bs.complement)
}

/// Alternation of patterns.
public func alt(_ patterns: RawRegex...) -> RawRegex {
  .alt(patterns)
}
