// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlueprintCreator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BlueprintCreator", targets: ["BlueprintCreator"]),
        .executable(name: "bcu", targets: ["BCUCLI"])
    ],
    targets: [
        .executableTarget(name: "BlueprintCreator", path: "Sources/BlueprintCreator"),
        .executableTarget(name: "BCUCLI", path: "Sources/BCUCLI")
    ]
)
