// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetX",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MeetX", targets: ["MeetX"])
    ],
    targets: [
        .executableTarget(
            name: "MeetX",
            path: "Sources/MeetX"
        )
    ]
)
