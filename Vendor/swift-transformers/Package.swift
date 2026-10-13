// swift-tools-version: 5.9
import PackageDescription

// A minimal, attributed distribution of swift-transformers 1.3.5's Hub and
// Tokenizers products, with one native app resource lookup fix. See UPSTREAM.md.
let package = Package(
    name: "swift-transformers",
    platforms: [.macOS(.v13)],
    products: [.library(name: "Hub", targets: ["Hub"]), .library(name: "Tokenizers", targets: ["Tokenizers"])],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-jinja.git", from: "2.4.2"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", "0.8.1"..<"2.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
        .package(url: "https://github.com/ibireme/yyjson.git", exact: "0.12.0")
    ],
    targets: [
        .target(name: "Hub", dependencies: [
            .product(name: "Jinja", package: "swift-jinja"),
            .product(name: "HuggingFace", package: "swift-huggingface"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "yyjson", package: "yyjson")
        ], resources: [.process("Resources")], swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "Tokenizers", dependencies: ["Hub", .product(name: "Jinja", package: "swift-jinja")])
    ]
)
