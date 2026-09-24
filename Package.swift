// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Miqat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Miqat", targets: ["Miqat"])
    ],
    dependencies: [
        .package(url: "https://github.com/batoulapps/adhan-swift.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "Miqat",
            dependencies: [
                .product(name: "Adhan", package: "adhan-swift")
            ],
            path: "Miqat",
            exclude: ["Info.plist", "Assets.xcassets"],
            sources: ["Sources"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "MiqatTests",
            dependencies: ["Miqat"],
            path: "MiqatTests"
        )
    ]
)
