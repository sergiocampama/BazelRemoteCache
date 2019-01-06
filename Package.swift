// swift-tools-version:4.2
import PackageDescription
import Foundation

var packageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/apple/swift-nio.git", .upToNextMinor(from: "1.12.0")),
  .package(url: "https://github.com/kylef/Commander.git", .upToNextMinor(from: "0.8.0")),
]

let package = Package(
  name: "RemoteCache",
  products: [
    .executable(name: "server", targets: ["server"]),
  ],
  dependencies: packageDependencies,
  targets: [
    .target(
      name: "RemoteCacheServer",
      dependencies: [
        "NIO",
        "NIOHTTP1",
      ]
    ),
    .target(
      name: "server",
      dependencies: [
        "Commander",
        "RemoteCacheServer",
      ]
    ),
    .testTarget(
      name: "RemoteCacheServerTests",
      dependencies: [
        "NIO",
        "NIOFoundationCompat",
        "RemoteCacheServer",
      ]
    ),
  ]
)
