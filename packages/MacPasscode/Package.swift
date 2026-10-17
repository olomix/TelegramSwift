// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "MacPasscode",
    platforms: [.macOS(.v12)],
    products: [
        .library(
            name: "MacPasscode",
            targets: ["MacPasscode"]),
    ],
    dependencies: [
        .package(name: "PasscodeCore", path: "../../submodules/telegram-ios/submodules/PasscodeCore"),
    ],
    targets: [
        .target(
            name: "MacPasscode",
            dependencies: [.product(name: "PasscodeCore", package: "PasscodeCore", condition: nil)]),
        .testTarget(
            name: "MacPasscodeTests",
            dependencies: ["MacPasscode",
                           .product(name: "PasscodeCore", package: "PasscodeCore", condition: nil)]),
    ]
)
