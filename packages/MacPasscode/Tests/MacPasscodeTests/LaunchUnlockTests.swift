import PasscodeCore
import XCTest
@testable import MacPasscode

/// One data folder plus keychain, surviving simulated crashes.
private final class World {
    let directory = URL(fileURLWithPath: "/data")
    let crash = CrashPoint()
    let storage: InMemoryStorage
    let store: FakeCredentialStore
    var accessChallenges: [PasscodeCredentialReference?] = []

    init() {
        self.storage = InMemoryStorage(crash: self.crash)
        self.store = FakeCredentialStore(crash: self.crash)
    }

    var unlock: LaunchUnlock {
        LaunchUnlock(databaseKeyFile: DatabaseKeyFile(directory: self.directory, storage: self.storage),
                     legacyKeyReader: LegacyKeyReader(directory: self.directory, storage: self.storage),
                     store: self.store,
                     storeAccessChallenge: { [unowned self] reference in
                         try self.crash.tick()
                         self.accessChallenges.append(reference)
                     })
    }

    var legacyURL: URL { self.unlock.legacyKeyReader.encryptedURL }
    var plaintextURL: URL { self.unlock.legacyKeyReader.plaintextURL }
    var v2URL: URL { self.unlock.databaseKeyFile.url }

    func installLegacy(_ databaseKey: DatabaseKey, passcode: String?) {
        self.storage.files[self.legacyURL] = LegacyFile.encrypt(databaseKey, passcode: passcode)
    }

    /// What the app does at launch: decide, then unlock with `code`.
    func launch(code: String?) throws -> DatabaseKey {
        let unlock = self.unlock
        switch try unlock.state() {
        case .legacy:
            return try unlock.unlockLegacy(code: code)
        case let .v2(needsPasscode):
            return try unlock.unlockV2(code: needsPasscode ? code : nil)
        case .fresh:
            return try unlock.createFresh()
        case .credentialLost:
            throw LaunchUnlockError.keyFileMissing
        }
    }
}

final class LaunchUnlockTests: XCTestCase {
    func testFreshInstall() throws {
        let world = World()
        XCTAssertEqual(try world.unlock.state(), .fresh)
        let databaseKey = try world.unlock.createFresh()
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: false))
        XCTAssertEqual(try world.unlock.unlockV2(code: nil), databaseKey)
        // A retired marker, so an older build never creates a key here.
        XCTAssertEqual(try world.unlock.legacyKeyReader.state(), .retired)
        XCTAssertEqual(world.accessChallenges, [nil])
    }

    func testFreshInstallResetsLeftoverProtectedCredential() throws {
        let world = World()
        world.store.credential = .init(code: "1234", kind: .digits4, protectionEnabled: true)
        _ = try world.unlock.createFresh()
        XCTAssertEqual(world.store.calls.first, "resetCredential")
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: false))
    }

    func testLegacyStates() throws {
        let world = World()
        world.installLegacy(.random(), passcode: nil)
        XCTAssertEqual(try world.unlock.state(), .legacy(needsPasscode: false))
        world.installLegacy(.random(), passcode: "1234")
        XCTAssertEqual(try world.unlock.state(), .legacy(needsPasscode: true))
    }

    func testLiveLegacyFileWinsOverV2() throws {
        // A crash after writing db-key.v2 but before retiring the old file.
        let world = World()
        world.installLegacy(.random(), passcode: "1234")
        world.storage.files[world.v2URL] = Data([1])
        XCTAssertEqual(try world.unlock.state(), .legacy(needsPasscode: true))
    }

    func testCredentialLostWhenKeychainItemIsGone() throws {
        let world = World()
        _ = try world.unlock.createFresh()
        world.store.credential = nil
        XCTAssertEqual(try world.unlock.state(), .credentialLost)
    }

    func testCredentialLostWhenV2IsGoneAfterMigration() throws {
        let world = World()
        world.installLegacy(.random(), passcode: nil)
        _ = try world.launch(code: nil)
        world.storage.files[world.v2URL] = nil
        XCTAssertEqual(try world.unlock.state(), .credentialLost)
        XCTAssertThrowsError(try world.unlock.createFresh())
    }

    func testStoreErrorsPropagate() {
        let world = World()
        _ = try? world.unlock.createFresh()
        world.store.failure = .keychain(-25300)
        XCTAssertThrowsError(try world.unlock.state()) {
            XCTAssertEqual($0 as? PasscodeError, .keychain(-25300))
        }
    }

    func testUnreadableKeyFilesNeverLeadToANewKey() throws {
        for unreadable in [\World.legacyURL, \World.plaintextURL, \World.v2URL] {
            let world = World()
            let url = world[keyPath: unreadable]
            world.storage.files[url] = Data(count: 64)
            world.storage.unreadable.insert(url)
            XCTAssertThrowsError(try world.unlock.state(), "\(url)")
            XCTAssertThrowsError(try world.unlock.createFresh(), "\(url)")
            XCTAssertTrue(world.storage.writes.isEmpty, "\(url)")
            XCTAssertTrue(world.store.calls.isEmpty, "\(url)")
        }
    }

    func testCreateFreshRefusesWhenAnyKeyFileExists() {
        for existing in [\World.legacyURL, \World.plaintextURL, \World.v2URL] {
            let world = World()
            world.storage.files[world[keyPath: existing]] = DatabaseKey.random().bytes
            XCTAssertThrowsError(try world.unlock.createFresh())
            XCTAssertTrue(world.storage.writes.isEmpty)
        }
    }

    func testMigratesLegacyPasscode() throws {
        let world = World()
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: "1234")
        XCTAssertEqual(try world.unlock.unlockLegacy(code: "1234"), databaseKey)

        XCTAssertEqual(world.store.credential?.kind, .digits4)
        XCTAssertEqual(world.store.credential?.protectionEnabled, true)
        XCTAssertEqual(world.accessChallenges, [world.store.reference])
        XCTAssertEqual(try world.unlock.legacyKeyReader.state(), .retired)
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: true))
        XCTAssertEqual(try world.unlock.unlockV2(code: "1234"), databaseKey)
        XCTAssertThrowsError(try world.unlock.unlockV2(code: nil))
    }

    func testMigratesLegacyWithoutPasscode() throws {
        let world = World()
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: nil)
        XCTAssertEqual(try world.unlock.unlockLegacy(code: nil), databaseKey)
        XCTAssertFalse(world.store.calls.contains("migrateLegacy"))
        XCTAssertEqual(world.accessChallenges, [nil])
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: false))
        XCTAssertEqual(try world.unlock.unlockV2(code: nil), databaseKey)
    }

    func testMigratesPlaintextTempkey() throws {
        let world = World()
        let databaseKey = DatabaseKey.random()
        world.storage.files[world.plaintextURL] = databaseKey.bytes
        XCTAssertEqual(try world.launch(code: nil), databaseKey)
        XCTAssertNil(world.storage.files[world.plaintextURL])
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: false))
    }

    func testMigratesNonAsciiDigitPasscode() throws {
        let world = World()
        let code = "\u{0661}\u{0662}\u{0663}\u{0664}"
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: code)
        XCTAssertEqual(try world.unlock.unlockLegacy(code: code), databaseKey)
        XCTAssertEqual(world.store.credential?.kind, .digits4)
        XCTAssertEqual(try world.unlock.unlockV2(code: code), databaseKey)
    }

    func testWrongLegacyCodeChangesNothing() throws {
        let world = World()
        world.installLegacy(.random(), passcode: "1234")
        let before = world.storage.files
        for code in ["1235", "", nil] as [String?] {
            XCTAssertThrowsError(try world.unlock.unlockLegacy(code: code)) {
                XCTAssertEqual($0 as? LaunchUnlockError, .invalidCode)
            }
        }
        XCTAssertEqual(world.storage.files, before)
        XCTAssertTrue(world.storage.writes.isEmpty)
        XCTAssertTrue(world.store.calls.isEmpty)
        XCTAssertNil(world.store.credential)
        XCTAssertTrue(world.accessChallenges.isEmpty)
    }

    func testWrongV2CodeChangesNothing() throws {
        let world = World()
        world.installLegacy(.random(), passcode: "1234")
        _ = try world.launch(code: "1234")
        let files = world.storage.files
        let writes = world.storage.writes.count
        XCTAssertThrowsError(try world.unlock.unlockV2(code: "0000")) {
            XCTAssertEqual($0 as? PasscodeError, .invalidCode)
        }
        XCTAssertEqual(world.storage.files, files)
        XCTAssertEqual(world.storage.writes.count, writes)
        XCTAssertEqual(world.store.credential?.protectionEnabled, true)
    }

    func testUnverifiedV2KeepsLegacyFileLive() throws {
        let world = World()
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: "1234")
        let legacy = world.storage.files[world.legacyURL]
        world.storage.corruptWrites = true
        XCTAssertThrowsError(try world.unlock.unlockLegacy(code: "1234"))
        XCTAssertEqual(world.storage.files[world.legacyURL], legacy)
        XCTAssertTrue(world.accessChallenges.isEmpty)

        world.storage.corruptWrites = false
        XCTAssertEqual(try world.launch(code: "1234"), databaseKey)
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: true))
    }

    func testMigrationInterruptedAfterEachStepResumes() throws {
        for passcode in ["1234", "pass word", nil] as [String?] {
            var step = 0
            while true {
                let world = World()
                let databaseKey = DatabaseKey.random()
                world.installLegacy(databaseKey, passcode: passcode)
                world.crash.remaining = step
                do {
                    _ = try world.launch(code: passcode)
                    break
                } catch is Crash {
                }
                // The next launch, with the same code, finishes the job.
                XCTAssertEqual(try world.launch(code: passcode), databaseKey, "step \(step)")
                XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: passcode != nil), "step \(step)")
                XCTAssertEqual(try world.unlock.legacyKeyReader.state(), .retired, "step \(step)")
                XCTAssertEqual(try world.unlock.unlockV2(code: passcode), databaseKey, "step \(step)")
                XCTAssertEqual(world.store.credential?.protectionEnabled, passcode != nil, "step \(step)")
                XCTAssertEqual(world.accessChallenges.last ?? nil, world.store.reference, "step \(step)")
                step += 1
            }
            XCTAssertGreaterThanOrEqual(step, passcode == nil ? 4 : 6, "\(String(describing: passcode))")
        }
    }

    func testFreshInstallInterruptedResumes() throws {
        var step = 0
        while true {
            let world = World()
            world.crash.remaining = step
            do {
                _ = try world.launch(code: nil)
                break
            } catch is Crash {
            }
            let databaseKey = try world.launch(code: nil)
            XCTAssertEqual(try world.launch(code: nil), databaseKey, "step \(step)")
            step += 1
        }
        XCTAssertGreaterThanOrEqual(step, 3)
    }

    func testLegacyMarkerCodeBecomesThePasscode() throws {
        let world = World()
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: nil)
        XCTAssertEqual(try world.unlock.unlockLegacy(code: nil, settingPasscode: "123456"), databaseKey)
        XCTAssertEqual(world.store.credential?.kind, .digits6)
        XCTAssertEqual(world.accessChallenges, [world.store.reference])
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: true))
        XCTAssertEqual(try world.unlock.unlockV2(code: "123456"), databaseKey)
    }

    func testMigrationReplacesCredentialWithAnotherCode() throws {
        let world = World()
        world.store.credential = .init(code: "0000", kind: .digits4, protectionEnabled: true, managed: true)
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: "1234")
        XCTAssertEqual(try world.launch(code: "1234"), databaseKey)
        XCTAssertTrue(world.store.calls.contains("resetCredential"))
        XCTAssertEqual(try world.unlock.unlockV2(code: "1234"), databaseKey)
        XCTAssertEqual(world.store.credential?.protectionEnabled, true)
    }

    func testMigrationSetsPasscodeOnResetCredential() throws {
        let world = World()
        world.store.credential = .init(managed: true)
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: "secret")
        XCTAssertEqual(try world.launch(code: "secret"), databaseKey)
        XCTAssertEqual(world.store.credential?.kind, .alphanumeric)
        XCTAssertFalse(world.store.calls.contains("resetCredential"))
        XCTAssertEqual(world.accessChallenges, [world.store.reference])
        XCTAssertEqual(try world.unlock.unlockV2(code: "secret"), databaseKey)
    }

    func testMigrationWithoutPasscodeResetsProtectedCredential() throws {
        let world = World()
        world.store.credential = .init(code: "0000", kind: .digits4, protectionEnabled: true, managed: true)
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: nil)
        XCTAssertEqual(try world.launch(code: nil), databaseKey)
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: false))
        XCTAssertEqual(try world.unlock.unlockV2(code: nil), databaseKey)
    }

    func testResetLocalSecretsDeletesKeyFilesBeforeTheCredential() throws {
        let world = World()
        world.installLegacy(.random(), passcode: "1234")
        _ = try world.launch(code: "1234")
        world.storage.files[world.plaintextURL] = Data(count: 48)
        var credentialDuringRemoval: String?
        try world.unlock.resetLocalSecrets(removingData: {
            credentialDuringRemoval = world.store.credential?.code
            XCTAssertNil(world.storage.files[world.v2URL])
            XCTAssertNil(world.storage.files[world.legacyURL])
        })
        XCTAssertEqual(credentialDuringRemoval, "1234")
        XCTAssertNil(world.storage.files[world.plaintextURL])
        XCTAssertEqual(world.store.credential?.protectionEnabled, false)
        XCTAssertEqual(try world.unlock.state(), .fresh)
        _ = try world.unlock.createFresh()
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: false))
    }

    func testFailedDataRemovalKeepsTheCredential() throws {
        let world = World()
        world.installLegacy(.random(), passcode: "1234")
        _ = try world.launch(code: "1234")
        XCTAssertThrowsError(try world.unlock.resetLocalSecrets(removingData: { throw Crash() }))
        XCTAssertEqual(world.store.credential?.code, "1234")
    }

    func testSealAfterResetKeepsTheRunningKey() throws {
        let world = World()
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: "1234")
        _ = try world.launch(code: "1234")
        XCTAssertThrowsError(try world.unlock.sealAfterReset(databaseKey)) {
            XCTAssertEqual($0 as? LaunchUnlockError, .keyFileExists)
        }
        try world.unlock.resetLocalSecrets(removingData: {})
        try world.unlock.sealAfterReset(databaseKey)
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: false))
        XCTAssertEqual(try world.unlock.unlockV2(code: nil), databaseKey)
        XCTAssertEqual(try world.unlock.legacyKeyReader.state(), .retired)
        XCTAssertEqual(world.accessChallenges.last, .some(nil))
    }
}
