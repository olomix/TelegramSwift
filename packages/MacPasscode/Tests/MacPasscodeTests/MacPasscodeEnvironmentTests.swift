import PasscodeCore
import XCTest
@testable import MacPasscode

final class MacPasscodeEnvironmentTests: XCTestCase {
    func testGroupsAndScope() throws {
        let environment = try XCTUnwrap(MacPasscodeEnvironment(teamPrefix: "2FKX9S8MFA.", buildPrefix: "debug"))
        XCTAssertEqual(environment.sharedAccessGroup, "2FKX9S8MFA.com.korthane.telex.shared")
        XCTAssertEqual(environment.privateAccessGroup, "2FKX9S8MFA.com.korthane.telex.private")
        XCTAssertEqual(environment.keychainScope, "com.korthane.telex.debug")
        XCTAssertEqual(MacPasscodeEnvironment(teamPrefix: "2FKX9S8MFA.", buildPrefix: "stable")?.keychainScope,
                       "com.korthane.telex.stable")
    }

    func testRejectsMissingOrUnexpandedPrefix() {
        for prefix in [nil, "", "$(AppIdentifierPrefix)", "2FKX9S8MFA", "2fkx9s8mfa.", "2FKX9S8MFA.com."] as [String?] {
            XCTAssertNil(MacPasscodeEnvironment(teamPrefix: prefix, buildPrefix: "debug"), String(describing: prefix))
        }
        XCTAssertNil(MacPasscodeEnvironment(teamPrefix: "2FKX9S8MFA.", buildPrefix: ""))
    }

    func testConfigurationPerRole() throws {
        let environment = try XCTUnwrap(MacPasscodeEnvironment(teamPrefix: "2FKX9S8MFA.", buildPrefix: "debug"))
        XCTAssertEqual(environment.configuration(for: .mainApp),
                       PasscodeConfiguration(appGroupIdentifier: "2FKX9S8MFA.com.korthane.telex.shared",
                                             processRole: .mainApp,
                                             biometricKeychainService: "telex.biometric",
                                             keychainScope: "com.korthane.telex.debug"))
        XCTAssertNil(environment.configuration(for: .appExtension).biometricKeychainService)
    }
}

final class PasscodeCheckFailureTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(PasscodeCheckFailure(PasscodeError.invalidCode), .invalidCode)
        XCTAssertEqual(PasscodeCheckFailure(LaunchUnlockError.invalidCode), .invalidCode)
        XCTAssertEqual(PasscodeCheckFailure(PasscodeError.cooldown(42)), .cooldown(seconds: 42))
        XCTAssertEqual(PasscodeCheckFailure(PasscodeError.cooldown(0)), .cooldown(seconds: 1))
        XCTAssertEqual(PasscodeCheckFailure(PasscodeError.keychain(-25300)), .unavailable)
        XCTAssertEqual(PasscodeCheckFailure(PasscodeError.authenticationRequired), .unavailable)
        XCTAssertEqual(PasscodeCheckFailure(DatabaseKeyFileError.authenticationFailed), .unavailable)
    }
}
