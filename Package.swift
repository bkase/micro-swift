// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MicroSwift",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "MicroSwiftSpec", targets: ["MicroSwiftSpec"]),
    .library(name: "MicroSwiftLexerGen", targets: ["MicroSwiftLexerGen"]),
    .library(name: "MicroSwiftTensorCore", targets: ["MicroSwiftTensorCore"]),
    .library(name: "MicroSwiftFrontend", targets: ["MicroSwiftFrontend"]),
    .library(name: "MicroSwiftWasm", targets: ["MicroSwiftWasm"]),
    .library(name: "MicroSwiftBench", targets: ["MicroSwiftBench"]),
    .executable(name: "micro-swift", targets: ["MicroSwiftCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.15.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.9.0"),
  ],
  targets: [
    .target(
      name: "MicroSwiftSpec",
      dependencies: []
    ),
    .target(name: "MicroSwiftLexerGen"),
    .target(name: "MicroSwiftTensorCore"),
    .target(name: "MicroSwiftFrontend"),
    .target(name: "MicroSwiftWasm"),
    .target(name: "MicroSwiftBench"),
    .executableTarget(
      name: "MicroSwiftCLI",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .target(name: "MicroSwiftSpec"),
        .product(name: "MLX", package: "mlx-swift"),
      ]
    ),
    .testTarget(
      name: "MicroSwiftSpecTests",
      dependencies: ["MicroSwiftSpec", .product(name: "CustomDump", package: "swift-custom-dump")]
    ),
    .testTarget(
      name: "MicroSwiftLexerGenTests",
      dependencies: ["MicroSwiftLexerGen"],
      path: "Tests/MicroSwiftLexerGenTests"
    ),
    .testTarget(
      name: "MicroSwiftTensorCoreTests",
      dependencies: ["MicroSwiftTensorCore"],
      path: "Tests/MicroSwiftTensorCoreTests"
    ),
    .testTarget(
      name: "MicroSwiftFrontendTests",
      dependencies: ["MicroSwiftFrontend"],
      path: "Tests/MicroSwiftFrontendTests"
    ),
    .testTarget(
      name: "MicroSwiftWasmTests",
      dependencies: ["MicroSwiftWasm"],
      path: "Tests/MicroSwiftWasmTests"
    ),
    .testTarget(
      name: "MicroSwiftBenchTests",
      dependencies: ["MicroSwiftBench"],
      path: "Tests/MicroSwiftBenchTests"
    ),
    .testTarget(
      name: "MicroSwiftCLITests",
      dependencies: [
        "MicroSwiftCLI",
        "MicroSwiftSpec",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      exclude: ["__Snapshots__"]
    ),
  ]
)
