// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clark",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Fixado por revisão (tag v1.19.0). O Package.resolved é versionado.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm",
                 revision: "464df5207fc2432e16c9a23abe538187196daf5f")
    ],
    targets: [
        .target(name: "ClarkCore", path: "Sources/ClarkCore"),
        .executableTarget(
            name: "Clark",
            dependencies: ["ClarkCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/Clark"
        ),
        .testTarget(name: "ClarkCoreTests", dependencies: ["ClarkCore"], path: "Tests/ClarkCoreTests"),
        .testTarget(name: "ClarkTests", dependencies: ["Clark", "ClarkCore"], path: "Tests/ClarkTests")
    ]
)
