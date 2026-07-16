// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "BluetoothGrab",
  platforms: [.macOS(.v13)],
  targets: [
    .executableTarget(
      name: "BluetoothGrab",
      path: "Sources/BluetoothGrab"
    ),
    .testTarget(
      name: "BluetoothGrabTests",
      dependencies: ["BluetoothGrab"],
      path: "Tests/BluetoothGrabTests"
    ),
  ]
)
