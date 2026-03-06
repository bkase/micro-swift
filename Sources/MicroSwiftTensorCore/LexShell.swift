import Foundation
import MicroSwiftFrontend

public enum LexShellError: Error, Sendable, Equatable {
  case pageOverflow(actual: Int, max: Int)
}

public struct LexShell: Sendable {
  public let lexingShell: LexingShell

  public init(lexingShell: LexingShell = LexingShell()) {
    self.lexingShell = lexingShell
  }

  public func lexFile(
    bytes: [UInt8],
    artifact: ArtifactRuntime,
    options: LexOptions
  ) throws -> [PageLexResult] {
    let source = SourceBuffer(
      fileID: FileID(rawValue: 0),
      path: "<memory>",
      bytes: Data(bytes)
    )
    let result = lexingShell.lexSource(source: source, artifact: artifact, options: options)
    return result.pageResults.map(\.result)
  }
}
