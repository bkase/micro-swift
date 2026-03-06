import Foundation

public struct BenchSeedManifest: Codable, Sendable, Equatable {
  public let schemaVersion: Int
  public let globalSeed: UInt64
  public let corpusSeeds: [CorpusID: UInt64]

  public init(
    schemaVersion: Int,
    globalSeed: UInt64,
    corpusSeeds: [CorpusID: UInt64]
  ) {
    self.schemaVersion = schemaVersion
    self.globalSeed = globalSeed
    self.corpusSeeds = corpusSeeds
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    globalSeed = try container.decode(UInt64.self, forKey: .globalSeed)

    let decoded = try container.decode([String: UInt64].self, forKey: .corpusSeeds)
    corpusSeeds = try Dictionary(
      uniqueKeysWithValues: decoded.map { (try CorpusID($0.key), $0.value) })
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(globalSeed, forKey: .globalSeed)

    let encoded = corpusSeeds.reduce(into: [String: UInt64]()) { partialResult, item in
      partialResult[item.key.rawValue] = item.value
    }
    try container.encode(encoded, forKey: .corpusSeeds)
  }

  public static func decode(from data: Data) throws -> BenchSeedManifest {
    let decoder = JSONDecoder()
    return try decoder.decode(BenchSeedManifest.self, from: data)
  }

  public func seed(for id: CorpusID) -> UInt64 {
    corpusSeeds[id] ?? globalSeed
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case globalSeed
    case corpusSeeds
  }
}
