import CustomDump
import Foundation
import MicroSwiftSpec
import Testing

@Suite
struct MicroSwiftSpecTests {
  @Test func decodesBenchSeedManifest() throws {
    let json = #"""
      {
        "schemaVersion": 1,
        "globalSeed": 1234,
        "corpusSeeds": {
          "spec": 111,
          "frontend": 222
        }
      }
      """#.utf8

    let manifest = try BenchSeedManifest.decode(from: Data(json))

    #expect(manifest.schemaVersion == 1)
    #expect(manifest.globalSeed == 1234)
    #expect(manifest.seed(for: .spec) == 111)
    #expect(manifest.seed(for: .bench) == 1234)
  }
}
