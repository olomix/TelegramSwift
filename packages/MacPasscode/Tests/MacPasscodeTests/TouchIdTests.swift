import PasscodeCore
import XCTest
@testable import MacPasscode

final class TouchIdPolicyTests: XCTestCase {
    func testToggleNeedsPasscode() {
        XCTAssertFalse(TouchIdPolicy.showsToggle(passcodeEnabled: false, biometricsEnabled: false, deviceSupportsBiometrics: true))
        XCTAssertFalse(TouchIdPolicy.showsToggle(passcodeEnabled: false, biometricsEnabled: true, deviceSupportsBiometrics: true))
        XCTAssertTrue(TouchIdPolicy.showsToggle(passcodeEnabled: true, biometricsEnabled: false, deviceSupportsBiometrics: true))
    }

    func testToggleStaysWhileOnWithoutSensor() {
        XCTAssertTrue(TouchIdPolicy.showsToggle(passcodeEnabled: true, biometricsEnabled: true, deviceSupportsBiometrics: false))
        XCTAssertFalse(TouchIdPolicy.showsToggle(passcodeEnabled: true, biometricsEnabled: false, deviceSupportsBiometrics: false))
    }

    func testUnlockNeedsEverything() {
        XCTAssertTrue(TouchIdPolicy.offersUnlock(passcodeEnabled: true, biometricsEnabled: true, deviceSupportsBiometrics: true))
        XCTAssertFalse(TouchIdPolicy.offersUnlock(passcodeEnabled: false, biometricsEnabled: true, deviceSupportsBiometrics: true))
        XCTAssertFalse(TouchIdPolicy.offersUnlock(passcodeEnabled: true, biometricsEnabled: false, deviceSupportsBiometrics: true))
        XCTAssertFalse(TouchIdPolicy.offersUnlock(passcodeEnabled: true, biometricsEnabled: true, deviceSupportsBiometrics: false))
    }
}

private final class CarryOverWorld {
    var legacySetting = true
    var passcodeEnabled = true
    var biometricsEnabled = false
    var deviceSupportsBiometrics = true
    var protectionFailure: PasscodeError?
    var enableFailure: PasscodeError?
    var enabledWith: [String] = []

    var carryOver: TouchIdCarryOver {
        TouchIdCarryOver(readLegacySetting: { self.legacySetting },
                         clearLegacySetting: { self.legacySetting = false },
                         protection: {
                             if let failure = self.protectionFailure { throw failure }
                             return (self.passcodeEnabled, self.biometricsEnabled)
                         },
                         deviceSupportsBiometrics: { self.deviceSupportsBiometrics },
                         enableBiometrics: { code in
                             self.enabledWith.append(code)
                             if let failure = self.enableFailure { throw failure }
                             self.biometricsEnabled = true
                         })
    }
}

final class TouchIdCarryOverTests: XCTestCase {
    func testEnablesWithTheUnlockCode() {
        let world = CarryOverWorld()
        XCTAssertEqual(world.carryOver.run(code: "1234"), .enabled)
        XCTAssertEqual(world.enabledWith, ["1234"])
        XCTAssertTrue(world.biometricsEnabled)
        XCTAssertFalse(world.legacySetting)
        XCTAssertEqual(world.carryOver.run(code: "1234"), .skipped)
        XCTAssertEqual(world.enabledWith.count, 1)
    }

    func testFailureIsTriedOnceAndDoesNotThrow() {
        for failure in [PasscodeError.cancelled, .biometricsUnavailable, .keychain(-25308)] {
            let world = CarryOverWorld()
            world.enableFailure = failure
            XCTAssertEqual(world.carryOver.run(code: "1234"), .failed)
            XCTAssertFalse(world.biometricsEnabled)
            XCTAssertFalse(world.legacySetting)
            XCTAssertEqual(world.carryOver.run(code: "1234"), .skipped)
            XCTAssertEqual(world.enabledWith.count, 1)
        }
    }

    func testNothingWithoutTheOldSetting() {
        let world = CarryOverWorld()
        world.legacySetting = false
        XCTAssertEqual(world.carryOver.run(code: "1234"), .skipped)
        XCTAssertTrue(world.enabledWith.isEmpty)
    }

    func testAlreadyEnabledOnlyClearsTheSetting() {
        let world = CarryOverWorld()
        world.biometricsEnabled = true
        XCTAssertEqual(world.carryOver.run(code: "1234"), .settingCleared)
        XCTAssertTrue(world.enabledWith.isEmpty)
        XCTAssertFalse(world.legacySetting)
    }

    func testNoPasscodeClearsTheSetting() {
        let world = CarryOverWorld()
        world.passcodeEnabled = false
        XCTAssertEqual(world.carryOver.run(code: "1234"), .settingCleared)
        XCTAssertTrue(world.enabledWith.isEmpty)
        XCTAssertFalse(world.legacySetting)
    }

    func testMissingSensorKeepsTheSettingForLater() {
        let world = CarryOverWorld()
        world.deviceSupportsBiometrics = false
        XCTAssertEqual(world.carryOver.run(code: "1234"), .skipped)
        XCTAssertTrue(world.legacySetting)
        world.deviceSupportsBiometrics = true
        XCTAssertEqual(world.carryOver.run(code: "1234"), .enabled)
    }

    func testUnreadableStoreKeepsTheSetting() {
        let world = CarryOverWorld()
        world.protectionFailure = .keychain(-25300)
        XCTAssertEqual(world.carryOver.run(code: "1234"), .skipped)
        XCTAssertTrue(world.legacySetting)
        XCTAssertTrue(world.enabledWith.isEmpty)
    }
}
