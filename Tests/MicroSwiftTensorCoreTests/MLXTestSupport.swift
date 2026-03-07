import Foundation

/// False under `swift test` (SPM), true under `xcodebuild test`.
let requiresMLXEval: Bool =
  ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
