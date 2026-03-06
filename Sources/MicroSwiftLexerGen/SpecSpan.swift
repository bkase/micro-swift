/// Source location of a DSL declaration, captured via #fileID / #line / #column.
public struct SpecSpan: Sendable, Equatable, Hashable, Codable {
  public let fileID: String
  public let line: Int
  public let column: Int

  public init(fileID: String, line: Int, column: Int) {
    self.fileID = fileID
    self.line = line
    self.column = column
  }
}
