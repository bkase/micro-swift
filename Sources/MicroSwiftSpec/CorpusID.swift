import Foundation

public enum CorpusID: String, Codable, Hashable, Sendable {
  case spec = "spec"
  case frontend = "frontend"
  case tensorCore = "tensor-core"
  case wasm = "wasm"
  case bench = "bench"

  public init(_ raw: String) {
    self = Self(rawValue: raw) ?? .spec
  }
}
