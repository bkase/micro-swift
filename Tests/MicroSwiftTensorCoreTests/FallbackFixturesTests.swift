import Foundation
import Testing
@testable import MicroSwiftLexerGen

@Suite
struct FallbackFixturesTests {
  @Test("Fallback fixtures JSON round-trip")
  func fixturesRoundTripAsJSON() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let decoder = JSONDecoder()

    for fixture in FallbackFixtures.all {
      let data = try encoder.encode(fixture)
      let decoded = try decoder.decode(LexerArtifact.self, from: data)
      #expect(decoded == fixture)
    }
  }
}
