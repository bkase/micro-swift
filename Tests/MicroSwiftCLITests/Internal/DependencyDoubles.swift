import Dependencies
import Foundation
import MicroSwiftCLI

public final class TestOutputCapture: @unchecked Sendable {
  private var output: String = ""

  public init() {}

  public func append(_ line: String) {
    output.append(line)
  }

  public func text() -> String {
    output
  }
}
