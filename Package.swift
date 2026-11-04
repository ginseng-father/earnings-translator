// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "EarningsTranslator",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "TranslatorCore"),
        .target(name: "TranslatorSystem", dependencies: ["TranslatorCore"]),
        .executableTarget(name: "EarningsTranslator", dependencies: ["TranslatorCore", "TranslatorSystem"]),
        .executableTarget(name: "TapProbe", dependencies: ["TranslatorCore", "TranslatorSystem"]),
        .executableTarget(name: "TranslateBench", dependencies: ["TranslatorCore", "TranslatorSystem"]),
        .testTarget(
            name: "TranslatorCoreTests",
            dependencies: ["TranslatorCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "TranslatorSystemTests", dependencies: ["TranslatorSystem"]),
    ]
)
