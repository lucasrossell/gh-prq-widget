// swift-tools-version:5.9
import PackageDescription

// PRQueueCore is plain Foundation (parsing, grouping, running the command) so its tests
// also run on Linux. The SwiftUI app target only exists when building on macOS.
var targets: [Target] = [
    .target(name: "PRQueueCore"),
    .testTarget(name: "PRQueueCoreTests", dependencies: ["PRQueueCore"]),
]
var products: [Product] = []

#if os(macOS)
targets.append(.executableTarget(name: "PRQueue", dependencies: ["PRQueueCore"]))
products.append(.executable(name: "PRQueue", targets: ["PRQueue"]))
#endif

let package = Package(
    name: "PRQueue",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
