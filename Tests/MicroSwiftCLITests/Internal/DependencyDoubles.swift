import Dependencies
import Foundation
import MicroSwiftCLI
import os

public final class TestOutputCapture: Sendable {
  private let storage = OSAllocatedUnfairLock(initialState: "")

  public init() {}

  public func append(_ line: String) {
    storage.withLock { $0.append(line) }
  }

  public func text() -> String {
    storage.withLock { $0 }
  }
}
