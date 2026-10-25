// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RepoServerApp",
    platforms: [
        .iOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "RepoServerApp",
            path: "Sources/RepoServerApp"
        )
    ]
)
