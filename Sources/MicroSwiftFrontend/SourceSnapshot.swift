import Foundation

// MARK: - Canonical snapshot model for JSON dumps

public struct SourceSnapshot: Codable, Hashable, Sendable {
  public let fileID: UInt32
  public let byteCount: Int64
  public let lineCount: Int32
  public let lineStartOffsets: [Int64]
  public let pages: [PageSnapshot]

  public struct PageSnapshot: Codable, Hashable, Sendable {
    public let pageID: Int32
    public let start: Int64
    public let end: Int64
    public let byteCount: Int32
    public let lineBreakCount: Int32
    public let oversize: Bool
  }
}

// MARK: - Dump generation

public enum SourceDump {
  public static func snapshot(from source: PreparedSource) -> SourceSnapshot {
    SourceSnapshot(
      fileID: source.buffer.fileID.rawValue,
      byteCount: Int64(source.buffer.bytes.count),
      lineCount: source.hostLineIndex.lineCount,
      lineStartOffsets: source.hostLineIndex.lineStartOffsets,
      pages: source.pages.map { page in
        SourceSnapshot.PageSnapshot(
          pageID: page.pageID,
          start: page.start.rawValue,
          end: page.end.rawValue,
          byteCount: page.byteCount,
          lineBreakCount: page.lineBreakCount,
          oversize: page.oversize
        )
      }
    )
  }

  public static func canonicalJSON(from source: PreparedSource) throws -> String {
    let snapshot = snapshot(from: source)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)
    return String(decoding: data, as: UTF8.self)
  }

  public static func textDump(from source: PreparedSource) -> String {
    let snap = snapshot(from: source)
    var out = ""
    out += "fileID: \(snap.fileID)\n"
    out += "byteCount: \(snap.byteCount)\n"
    out += "lineCount: \(snap.lineCount)\n"
    out += "lineStartOffsets: \(snap.lineStartOffsets)\n"
    out += "pages:\n"
    for p in snap.pages {
      out += "  page \(p.pageID): [\(p.start), \(p.end)) bytes=\(p.byteCount)"
      out += " lineBreaks=\(p.lineBreakCount)"
      if p.oversize { out += " OVERSIZE" }
      out += "\n"
    }
    return out
  }
}
