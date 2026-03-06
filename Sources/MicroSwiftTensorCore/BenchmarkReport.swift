import Foundation

public enum BenchmarkReport {
  public static func toJSON(_ result: LexBenchmarkResult) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard
      let data = try? encoder.encode(result),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return json
  }

  public static func printReport(_ result: LexBenchmarkResult) {
    Swift.print(toJSON(result))
  }
}
