import ArgumentParser
import Dependencies
import Foundation

@main
public struct MicroSwift: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "micro-swift",
    abstract: "Local-first tooling shell for MicroSwift",
    subcommands: [
      Doctor.self,
      Seed.self,
      MLXSmoke.self,
      LexerGen.self,
    ]
  )

  public init() {}
}

extension URL {
  fileprivate static func from(_ path: String) -> URL {
    URL(fileURLWithPath: path)
  }
}
