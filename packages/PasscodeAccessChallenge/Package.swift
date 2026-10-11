// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "PasscodeAccessChallenge",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(
            name: "PasscodeAccessChallenge",
            targets: ["PasscodeAccessChallenge"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
    ],
    targets: [
        .target(
            name: "PasscodeAccessChallenge",
            dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                           .product(name: "Postbox", package: "Postbox", condition: nil),
                           .product(name: "TelegramCore", package: "TelegramCore", condition: nil)]),
        .testTarget(
            name: "PasscodeAccessChallengeTests",
            dependencies: ["PasscodeAccessChallenge",
                           .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                           .product(name: "TelegramCore", package: "TelegramCore", condition: nil)]),
    ]
)
