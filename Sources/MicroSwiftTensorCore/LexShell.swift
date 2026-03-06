import Foundation
import MicroSwiftFrontend

public enum LexShellError: Error, Sendable, Equatable {
  case pageOverflow(actual: Int, max: Int)
}

public struct LexShell: Sendable {
  public init() {}

  public func lexFile(
    bytes: [UInt8],
    artifact: ArtifactRuntime,
    options: LexOptions
  ) throws -> [PageLexResult] {
    let maxSupportedBucket = pageCapacity(for: artifact)
    let pages = plannedPages(for: bytes, targetBytes: maxSupportedBucket)
    var results: [PageLexResult] = []

    for page in pages {
      let pageLen = Int(page.byteCount)
      let pageBucket = pageBucketSize(for: pageLen)
      guard pageBucket <= maxSupportedBucket else {
        throw LexShellError.pageOverflow(actual: pageLen, max: maxSupportedBucket)
      }

      let start = Int(page.start.rawValue)
      let end = Int(page.end.rawValue)
      let pageBytes = Array(bytes[start..<end])
      let pageResult = lexPage(
        bytes: pageBytes,
        validLen: Int32(pageLen),
        baseOffset: page.start.rawValue,
        artifact: artifact,
        options: options
      )
      results.append(pad(result: pageResult, to: pageBucket))
    }

    return results
  }

  private func pageCapacity(for artifact: ArtifactRuntime) -> Int {
    let lookahead = Int(artifact.runtimeHints.maxDeterministicLookaheadBytes)
    if lookahead > 0 { return lookahead }
    return max(1, Int(artifact.runtimeHints.maxBoundedRuleWidth))
  }

  private func plannedPages(for bytes: [UInt8], targetBytes: Int) -> [SourcePage] {
    let sourceData = Data(bytes)
    let lineStarts = LineStructure.lineStartOffsets(bytes: sourceData)
    return SourcePaging.planPages(
      lineStartOffsets: lineStarts,
      byteCount: Int64(bytes.count),
      policy: PagePolicy(targetBytes: Int32(targetBytes))
    )
  }

  private func pageBucketSize(for pageLen: Int) -> Int {
    var bucket = 1
    while bucket < max(pageLen, 1) {
      bucket <<= 1
    }
    return bucket
  }

  private func pad(result: PageLexResult, to width: Int) -> PageLexResult {
    guard result.packedRows.count < width else {
      return result
    }
    let padded =
      result.packedRows + Array(repeating: UInt64(0), count: width - result.packedRows.count)
    return PageLexResult(packedRows: padded, rowCount: result.rowCount)
  }
}
