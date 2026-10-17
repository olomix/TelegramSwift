@testable import PasscodeCore
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

    func testConfigureMainApp() throws {
        let environment = try XCTUnwrap(MacPasscodeEnvironment(teamPrefix: "2FKX9S8MFA.", buildPrefix: "debug"))
        let passcodeEnvironment = PasscodeEnvironment()
        let store = PasscodeCredentialStore(storage: InMemoryPasscodeStorage())
        try environment.configure(.mainApp, environment: passcodeEnvironment, store: store)
        XCTAssertTrue(passcodeEnvironment.isMainApp)
        XCTAssertEqual(try passcodeEnvironment.sharedAccessGroup(), "2FKX9S8MFA.com.korthane.telex.shared")
        XCTAssertEqual(try passcodeEnvironment.privateAccessGroup(), "2FKX9S8MFA.com.korthane.telex.private")
        XCTAssertEqual(try passcodeEnvironment.biometricKeychainService(), "telex.biometric")
        // The app may create the first credential.
        XCTAssertFalse(try store.protectionSettings().enabled)
    }

    func testConfigureExtension() throws {
        let environment = try XCTUnwrap(MacPasscodeEnvironment(teamPrefix: "2FKX9S8MFA.", buildPrefix: "debug"))
        let passcodeEnvironment = PasscodeEnvironment()
        let store = PasscodeCredentialStore(storage: InMemoryPasscodeStorage())
        try environment.configure(.appExtension, environment: passcodeEnvironment, store: store)
        XCTAssertFalse(passcodeEnvironment.isMainApp)
        XCTAssertEqual(try passcodeEnvironment.sharedAccessGroup(), "2FKX9S8MFA.com.korthane.telex.shared")
        XCTAssertThrowsError(try passcodeEnvironment.privateAccessGroup())
        XCTAssertThrowsError(try passcodeEnvironment.biometricKeychainService())
        // The extension must never create a credential.
        XCTAssertThrowsError(try store.unprotectedSession(namespace: CoreLaunchCredentialStore.namespace)) {
            XCTAssertEqual($0 as? PasscodeError, .unavailable)
        }
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

    func testCooldownText() {
        XCTAssertEqual(PasscodeTexts.cooldown(seconds: 42), "Too many attempts. Try again in 42 s.")
    }
}
