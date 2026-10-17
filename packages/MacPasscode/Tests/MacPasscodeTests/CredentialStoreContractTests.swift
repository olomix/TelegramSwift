import CryptoKit
import Foundation
import PasscodeCore
import XCTest
@testable import MacPasscode

/// The PasscodeCore behaviour `LaunchUnlock` relies on, checked against both
/// `FakeCredentialStore` and the real store over in-memory keychain items,
/// so the fake cannot drift from PasscodeCore unnoticed.
final class CredentialStoreContractTests: XCTestCase {
    private func stores() -> [(String, LaunchCredentialStore)] {
        [("fake", FakeCredentialStore()), ("real", CoreLaunchCredentialStore.inMemory())]
    }

    private func bytes(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    func testEmptyStore() throws {
        for (name, store) in self.stores() {
            XCTAssertFalse(try store.hasStoredCredential(), name)
            XCTAssertFalse(try store.isProtectionEnabled(), name)
            XCTAssertFalse(try store.hasPasscode(), name)
            XCTAssertFalse(try store.isManaged(), name)
            XCTAssertFalse(try store.isBiometricsEnabled(), name)
        }
    }

    func testUnprotectedSessionCreatesAnUnmanagedCredential() throws {
        for (name, store) in self.stores() {
            let key = try store.databaseSealingKey(code: nil)
            XCTAssertTrue(try store.hasStoredCredential(), name)
            XCTAssertFalse(try store.isManaged(), name)
            XCTAssertEqual(self.bytes(try store.databaseSealingKey(code: nil)), self.bytes(key), name)
        }
    }

    func testMigrationKeepsTheAccessKeyAndIsIdempotent() throws {
        for (name, store) in self.stores() {
            let unprotected = try store.databaseSealingKey(code: nil)
            let reference = try XCTUnwrap(try store.migrateLegacy(code: "1234", kind: .digits4), name)
            XCTAssertTrue(try store.isManaged(), name)
            XCTAssertTrue(try store.hasPasscode(), name)
            XCTAssertFalse(try store.isProtectionEnabled(), name)
            XCTAssertEqual(try store.migrateLegacy(code: "5678", kind: .digits4), reference, name)

            try store.enableProtection(code: "1234")
            XCTAssertTrue(try store.isProtectionEnabled(), name)
            XCTAssertThrowsError(try store.databaseSealingKey(code: nil), name)
            XCTAssertThrowsError(try store.databaseSealingKey(code: "5678"), name) {
                XCTAssertEqual($0 as? PasscodeError, .invalidCode, name)
            }
            XCTAssertEqual(self.bytes(try store.databaseSealingKey(code: "1234")), self.bytes(unprotected), name)
        }
    }

    func testWrongCodeDoesNotEnableProtection() throws {
        for (name, store) in self.stores() {
            _ = try store.migrateLegacy(code: "1234", kind: .digits4)
            XCTAssertThrowsError(try store.enableProtection(code: "0000"), name) {
                XCTAssertEqual($0 as? PasscodeError, .invalidCode, name)
            }
            XCTAssertFalse(try store.isProtectionEnabled(), name)
        }
    }

    func testResetGivesAManagedCredentialWithoutPasscode() throws {
        for (name, store) in self.stores() {
            _ = try store.migrateLegacy(code: "1234", kind: .digits4)
            try store.enableProtection(code: "1234")
            let protected = try store.databaseSealingKey(code: "1234")
            var removed = false
            try store.resetCredential(removingProtectedData: { removed = true })
            XCTAssertTrue(removed, name)
            XCTAssertTrue(try store.isManaged(), name)
            XCTAssertFalse(try store.hasPasscode(), name)
            XCTAssertFalse(try store.isProtectionEnabled(), name)
            let reset = try store.databaseSealingKey(code: nil)
            XCTAssertNotEqual(self.bytes(reset), self.bytes(protected), name)

            // A reset credential counts as migrated: no code is adopted.
            XCTAssertNil(try store.migrateLegacy(code: "1234", kind: .digits4), name)
            XCTAssertFalse(try store.hasPasscode(), name)
            _ = try store.setInitialPasscode(code: "4321", kind: .digits4)
            XCTAssertTrue(try store.isProtectionEnabled(), name)
            XCTAssertEqual(self.bytes(try store.databaseSealingKey(code: "4321")), self.bytes(reset), name)
            XCTAssertThrowsError(try store.setInitialPasscode(code: "1111", kind: .digits4), name)
        }
    }

    func testFailedRemovalKeepsTheCredential() throws {
        for (name, store) in self.stores() {
            _ = try store.migrateLegacy(code: "1234", kind: .digits4)
            try store.enableProtection(code: "1234")
            XCTAssertThrowsError(try store.resetCredential(removingProtectedData: { throw Crash() }), name)
            XCTAssertTrue(try store.isProtectionEnabled(), name)
            XCTAssertNoThrow(try store.databaseSealingKey(code: "1234"), name)
        }
    }
}
