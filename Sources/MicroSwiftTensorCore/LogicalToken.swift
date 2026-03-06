public struct LogicalToken: Sendable, Equatable {
  public let kind: UInt16
  public let flags: UInt8
  public let startByte: Int64
  public let endByte: Int64
  public let payloadA: UInt32
  public let payloadB: UInt32

  public init(
    kind: UInt16,
    flags: UInt8,
    startByte: Int64,
    endByte: Int64,
    payloadA: UInt32,
    payloadB: UInt32
  ) {
    self.kind = kind
    self.flags = flags
    self.startByte = startByte
    self.endByte = endByte
    self.payloadA = payloadA
    self.payloadB = payloadB
  }
}
