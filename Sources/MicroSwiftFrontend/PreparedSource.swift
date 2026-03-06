import Foundation
import MLX

// MARK: - SourceTape

public struct SourceTape: @unchecked Sendable {
  public let fileID: FileID
  public let byteCount: Int64
  public let bytes: MLXArray
  public let lineStartOffsets: MLXArray
  public let lineCount: Int32
}

// MARK: - PreparedSource

public struct PreparedSource: Sendable {
  public let buffer: SourceBuffer
  public let tape: SourceTape?
  public let hostLineIndex: HostLineIndex
  public let pages: [SourcePage]
}

// MARK: - SourceLoader errors

public enum SourceLoadError: Error, Equatable {
  case readFailed(String)
}

// MARK: - SourceLoader

public enum SourceLoader {
  /// Load a file and prepare (host-only, no MLX tape).
  public static func load(
    fileID: FileID,
    path: String,
    pagePolicy: PagePolicy,
    readFile: (String) throws -> Data
  ) throws -> PreparedSource {
    let data: Data
    do {
      data = try readFile(path)
    } catch {
      throw SourceLoadError.readFailed(path)
    }

    return prepareHostOnly(fileID: fileID, path: path, bytes: data, pagePolicy: pagePolicy)
  }

  /// Load a file and prepare with MLX tape.
  public static func loadWithTape(
    fileID: FileID,
    path: String,
    pagePolicy: PagePolicy,
    readFile: (String) throws -> Data
  ) throws -> PreparedSource {
    let data: Data
    do {
      data = try readFile(path)
    } catch {
      throw SourceLoadError.readFailed(path)
    }

    return prepare(fileID: fileID, path: path, bytes: data, pagePolicy: pagePolicy)
  }

  /// Full prepare with MLX tape.
  public static func prepare(
    fileID: FileID,
    path: String,
    bytes: Data,
    pagePolicy: PagePolicy
  ) -> PreparedSource {
    let (buffer, hostIndex, pages) = prepareCore(
      fileID: fileID, path: path, bytes: bytes, pagePolicy: pagePolicy)

    let byteArray = bytes.withUnsafeBytes { buf in
      MLXArray(buf.bindMemory(to: UInt8.self), [bytes.count])
    }
    let lineStartArray = MLXArray(hostIndex.lineStartOffsets.map { Int64($0) })

    let tape = SourceTape(
      fileID: fileID,
      byteCount: Int64(bytes.count),
      bytes: byteArray,
      lineStartOffsets: lineStartArray,
      lineCount: hostIndex.lineCount
    )

    return PreparedSource(
      buffer: buffer,
      tape: tape,
      hostLineIndex: hostIndex,
      pages: pages
    )
  }

  /// Prepare without MLX tape (for tests or environments without Metal).
  public static func prepareHostOnly(
    fileID: FileID,
    path: String,
    bytes: Data,
    pagePolicy: PagePolicy
  ) -> PreparedSource {
    let (buffer, hostIndex, pages) = prepareCore(
      fileID: fileID, path: path, bytes: bytes, pagePolicy: pagePolicy)
    return PreparedSource(
      buffer: buffer,
      tape: nil,
      hostLineIndex: hostIndex,
      pages: pages
    )
  }

  private static func prepareCore(
    fileID: FileID,
    path: String,
    bytes: Data,
    pagePolicy: PagePolicy
  ) -> (SourceBuffer, HostLineIndex, [SourcePage]) {
    let buffer = SourceBuffer(fileID: fileID, path: path, bytes: bytes)
    let hostIndex = LineStructure.hostLineIndex(bytes: bytes)
    let pages = SourcePaging.planPages(
      lineStartOffsets: hostIndex.lineStartOffsets,
      byteCount: Int64(bytes.count),
      policy: pagePolicy
    )
    return (buffer, hostIndex, pages)
  }
}

// MARK: - SourceQueries

public enum SourceQueries {
  public static func resolve(
    _ offset: ByteOffset,
    in source: PreparedSource
  ) -> SourceLocation {
    SourceResolver.resolve(
      offset,
      fileID: source.buffer.fileID,
      hostLineIndex: source.hostLineIndex
    )
  }

  public static func makeSpan(
    fileID: FileID,
    start: ByteOffset,
    end: ByteOffset,
    in source: PreparedSource
  ) throws -> Span {
    try Span.validated(
      fileID: fileID,
      start: start,
      end: end,
      in: source.buffer
    )
  }
}
