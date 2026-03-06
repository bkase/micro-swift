import Foundation

public enum CorpusID: String, Codable, Hashable, Sendable {
  case spec = "spec"
  case frontend = "frontend"
  case tensorCore = "tensor-core"
  case wasm = "wasm"
  case bench = "bench"

  public init(_ raw: String) throws {
    guard let value = Self(rawValue: raw) else {
      throw CorpusIDError.unknownCorpus(raw)
    }
    self = value
  }

  public enum CorpusIDError: Error {
    case unknownCorpus(String)
  }
}
