// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chorus",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Chorus", targets: ["Chorus"]),
               .executable(name: "chorus-check", targets: ["ChorusCheck"]),
               .executable(name: "chorus-tests", targets: ["ChorusTests"])],
    dependencies: [
        .package(path: "Vendor/swift-transformers"),
        .package(path: "Vendor/mlx-swift"),
        .package(url: "https://github.com/Jud/kokoro-coreml.git", revision: "6bfc02afb237a311caee927482e58c028edb6acb"),
        .package(url: "https://github.com/iliasaz/chatterbox-coreml.git", revision: "b8288834e783f3a6210757fbaf62f9014220bff9"),
        .package(url: "https://github.com/iliasaz/perth-coreml.git", branch: "main")
    ],
    targets: [
        .target(name: "ChorusKit"),
        .target(name: "ChorusPocket", dependencies: ["ChorusKit", .product(name: "MLX", package: "mlx-swift"), .product(name: "MLXNN", package: "mlx-swift"), .product(name: "MLXFast", package: "mlx-swift"), .product(name: "MLXRandom", package: "mlx-swift")], exclude: ["UPSTREAM.md", "LICENSE-UPSTREAM"]),
        .target(name: "ChorusKokoro", dependencies: ["ChorusKit", .product(name: "KokoroCoreML", package: "kokoro-coreml")]),
        .executableTarget(name: "Chorus", dependencies: ["ChorusKit", "ChorusKokoro", "ChorusPocket",
            .product(name: "ChatterboxCoreML", package: "chatterbox-coreml"),
            .product(name: "PerthCoreML", package: "perth-coreml")], resources: [.copy("Resources/Voices")]),
        .executableTarget(name: "ChorusCheck", dependencies: ["ChorusKit", "ChorusKokoro", "ChorusPocket",
            .product(name: "ChatterboxCoreML", package: "chatterbox-coreml"),
            .product(name: "PerthCoreML", package: "perth-coreml")]),
        .executableTarget(name: "ChorusTests", dependencies: ["ChorusKit"], path: "Tests/ChorusKitTests")
    ],
    swiftLanguageModes: [.v5]
)
