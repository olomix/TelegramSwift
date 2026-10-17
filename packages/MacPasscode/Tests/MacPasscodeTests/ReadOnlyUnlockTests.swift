import PasscodeCore
import XCTest
@testable import MacPasscode

final class ReadOnlyUnlockTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/data")
    private var storage: InMemoryStorage!
    private var store: FakeCredentialStore!

    override func setUp() {
        self.storage = InMemoryStorage()
        self.store = FakeCredentialStore()
    }

    private var launchUnlock: LaunchUnlock {
        LaunchUnlock(databaseKeyFile: DatabaseKeyFile(directory: self.directory, storage: self.storage),
                     legacyKeyFile: LegacyKeyFile(directory: self.directory, storage: self.storage),
                     store: self.store,
                     storeAccessChallenge: { _ in })
    }

    private var unlock: ReadOnlyUnlock {
        ReadOnlyUnlock(directory: self.directory, credentials: self.store, storage: self.storage)
    }

    private var legacyURL: URL { self.launchUnlock.legacyKeyFile.encryptedURL }
    private var v2URL: URL { self.launchUnlock.databaseKeyFile.url }

    /// What the app leaves after migrating an old key file.
    private func migrated(passcode: String?) throws -> DatabaseKey {
        let databaseKey = DatabaseKey.random()
        self.storage.files[self.legacyURL] = LegacyFile.encrypt(databaseKey, passcode: passcode)
        XCTAssertEqual(try self.launchUnlock.unlockLegacy(code: passcode), databaseKey)
        return databaseKey
    }

    /// Runs `body`, then checks that no file, credential or store call
    /// changed state.
    private func assertNoChanges(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) rethrows {
        let files = self.storage.files
        let writes = self.storage.writes.count
        let credential = self.store.credential.map { ($0.id, $0.code, $0.protectionEnabled, $0.managed) }
        let calls = self.store.calls.count
        try body()
        XCTAssertEqual(self.storage.files, files, "files changed", file: file, line: line)
        XCTAssertEqual(self.storage.writes.count, writes, "files written", file: file, line: line)
        let after = self.store.credential.map { ($0.id, $0.code, $0.protectionEnabled, $0.managed) }
        XCTAssertEqual(after?.0, credential?.0, file: file, line: line)
        XCTAssertEqual(after?.1, credential?.1, file: file, line: line)
        XCTAssertEqual(after?.2, credential?.2, file: file, line: line)
        XCTAssertEqual(after?.3, credential?.3, file: file, line: line)
        XCTAssertEqual(after == nil, credential == nil, "credential created or removed", file: file, line: line)
        let newCalls = Array(self.store.calls.dropFirst(calls))
        XCTAssertTrue(newCalls.allSatisfy { $0 == "databaseSealingKey" }, "\(newCalls)", file: file, line: line)
    }

    func testUnlocksWithoutPasscode() throws {
        let databaseKey = try self.migrated(passcode: nil)
        try self.assertNoChanges {
            XCTAssertEqual(try self.unlock.state(), .ready(needsPasscode: false))
            XCTAssertEqual(try self.unlock.unlock(code: nil), databaseKey)
            XCTAssertEqual(try self.unlock.unlock(code: "1234"), databaseKey)
        }
    }

    func testUnlocksFreshInstallKey() throws {
        let databaseKey = try self.launchUnlock.createFresh()
        try self.assertNoChanges {
            XCTAssertEqual(try self.unlock.state(), .ready(needsPasscode: false))
            XCTAssertEqual(try self.unlock.unlock(code: nil), databaseKey)
        }
    }

    func testUnlocksWithPasscode() throws {
        let databaseKey = try self.migrated(passcode: "1234")
        try self.assertNoChanges {
            XCTAssertEqual(try self.unlock.state(), .ready(needsPasscode: true))
            XCTAssertEqual(try self.unlock.unlock(code: "1234"), databaseKey)
        }
    }

    func testWrongCodeChangesNothing() throws {
        let databaseKey = try self.migrated(passcode: "1234")
        try self.assertNoChanges {
            XCTAssertThrowsError(try self.unlock.unlock(code: "4321")) { error in
                XCTAssertEqual(error as? PasscodeError, .invalidCode)
                XCTAssertEqual(PasscodeCheckFailure(error), .invalidCode)
            }
            XCTAssertThrowsError(try self.unlock.unlock(code: nil))
        }
        XCTAssertEqual(try self.unlock.unlock(code: "1234"), databaseKey)
    }

    func testCooldownPassesThrough() throws {
        _ = try self.migrated(passcode: "1234")
        self.store.sealingKeyFailure = .cooldown(42)
        try self.assertNoChanges {
            XCTAssertThrowsError(try self.unlock.unlock(code: "1234")) { error in
                XCTAssertEqual(PasscodeCheckFailure(error), .cooldown(seconds: 42))
            }
        }
    }

    func testLiveLegacyFileNeedsAppLaunch() throws {
        for passcode in [nil, "1234"] as [String?] {
            self.setUp()
            self.storage.files[self.legacyURL] = LegacyFile.encrypt(DatabaseKey.random(), passcode: passcode)
            try self.assertNoChanges {
                XCTAssertEqual(try self.unlock.state(), .needsAppLaunch)
                XCTAssertThrowsError(try self.unlock.unlock(code: passcode)) { error in
                    XCTAssertEqual(error as? ReadOnlyUnlockError, .needsAppLaunch)
                }
            }
            XCTAssertTrue(self.store.calls.isEmpty, "\(self.store.calls)")
            XCTAssertNil(self.store.credential)
        }
    }

    func testPlaintextLegacyKeyNeedsAppLaunch() throws {
        self.storage.files[self.launchUnlock.legacyKeyFile.plaintextURL] = DatabaseKey.random().bytes
        try self.assertNoChanges {
            XCTAssertEqual(try self.unlock.state(), .needsAppLaunch)
        }
    }

    func testUnfinishedMigrationNeedsAppLaunch() throws {
        let databaseKey = try self.migrated(passcode: "1234")
        // A crash before `retire()`: the old file is live next to `db-key.v2`.
        self.storage.files[self.legacyURL] = LegacyFile.encrypt(databaseKey, passcode: "1234")
        try self.assertNoChanges {
            XCTAssertEqual(try self.unlock.state(), .needsAppLaunch)
            XCTAssertThrowsError(try self.unlock.unlock(code: "1234"))
        }
    }

    func testNoKeyNeedsAppLaunchAndCreatesNothing() throws {
        try self.assertNoChanges {
            XCTAssertEqual(try self.unlock.state(), .needsAppLaunch)
            XCTAssertThrowsError(try self.unlock.unlock(code: nil)) { error in
                XCTAssertEqual(error as? ReadOnlyUnlockError, .needsAppLaunch)
            }
        }
        XCTAssertNil(self.store.credential)
        XCTAssertTrue(self.storage.files.isEmpty)
    }

    func testCredentialLost() throws {
        _ = try self.migrated(passcode: "1234")
        self.store.credential = nil
        try self.assertNoChanges {
            XCTAssertEqual(try self.unlock.state(), .credentialLost)
            XCTAssertThrowsError(try self.unlock.unlock(code: "1234")) { error in
                XCTAssertEqual(error as? ReadOnlyUnlockError, .credentialLost)
                XCTAssertEqual(PasscodeCheckFailure(error), .unavailable)
            }
        }
        XCTAssertNil(self.store.credential)
    }

    func testRetiredFileWithoutV2IsCredentialLost() throws {
        _ = try self.migrated(passcode: nil)
        self.storage.files[self.v2URL] = nil
        try self.assertNoChanges {
            XCTAssertEqual(try self.unlock.state(), .credentialLost)
        }
    }

    func testKeychainErrorThrows() throws {
        _ = try self.migrated(passcode: "1234")
        self.store.failure = .keychain(-25300)
        try self.assertNoChanges {
            XCTAssertThrowsError(try self.unlock.state()) { error in
                XCTAssertEqual(error as? PasscodeError, .keychain(-25300))
                XCTAssertEqual(PasscodeCheckFailure(error), .unavailable)
            }
        }
    }

    func testUnreadableKeyFileThrows() throws {
        _ = try self.migrated(passcode: nil)
        self.storage.unreadable.insert(self.v2URL)
        XCTAssertThrowsError(try self.unlock.state())
    }

    func testStorageRefusesWrites() throws {
        let base = InMemoryStorage()
        let url = URL(fileURLWithPath: "/data/file")
        base.files[url] = Data([1])
        let storage = ReadOnlyKeyFileStorage(base)
        XCTAssertEqual(try storage.read(url), Data([1]))
        XCTAssertThrowsError(try storage.writeAtomically(Data([2]), to: url)) { error in
            XCTAssertEqual(error as? ReadOnlyUnlockError, .readOnly)
        }
        XCTAssertThrowsError(try storage.remove(url)) { error in
            XCTAssertEqual(error as? ReadOnlyUnlockError, .readOnly)
        }
        XCTAssertEqual(base.files, [url: Data([1])])
        XCTAssertTrue(base.writes.isEmpty)
    }
}
