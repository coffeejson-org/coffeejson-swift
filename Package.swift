// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CoffeeJSON",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "CoffeeJSON",
            targets: ["CoffeeJSON"]
        ),
        // For test targets: the conformance gate a producer of this format
        // needs against itself. Vended rather than copied, so every consumer's
        // gate asks the same question of the same schema with the same
        // keywords. Never link it into a shipping target.
        .library(
            name: "CoffeeJSONSchemaTesting",
            targets: ["CoffeeJSONSchemaTesting"]
        ),
    ],
    targets: [
        .target(
            name: "CoffeeJSON"
        ),
        .target(
            name: "CoffeeJSONSchemaTesting"
        ),
        .testTarget(
            name: "CoffeeJSONTests",
            dependencies: ["CoffeeJSON", "CoffeeJSONSchemaTesting"]
        ),
    ]
)
