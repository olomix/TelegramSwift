import LocalAuthentication
import PasscodeCore
import XCTest
@testable import MacPasscode

/// One data folder, keychain and account manager, surviving simulated
/// crashes. The real-store variant runs PasscodeCore over in-memory items.
private final class World {
    let directory = URL(fileURLWithPath: "/data")
    let crash = CrashPoint()
    let storage: InMemoryStorage
    let store: FakeCredentialStore
    let launchStore: LaunchCredentialStore
    var accessChallenges: [PasscodeCredentialReference?] = []
    /// A non-empty code an old build kept in the account manager itself.
    var marker: String?

    init(realStore: Bool = false) {
        self.storage = InMemoryStorage(crash: self.crash)
        self.store = FakeCredentialStore(crash: self.crash)
        self.launchStore = realStore ? CrashingCredentialStore(CoreLaunchCredentialStore.inMemory(), crash: self.crash) : self.store
    }

    var unlock: LaunchUnlock {
        LaunchUnlock(databaseKeyFile: DatabaseKeyFile(directory: self.directory, storage: self.storage),
                     legacyKeyReader: LegacyKeyReader(directory: self.directory, storage: self.storage),
                     store: self.launchStore,
                     storeAccessChallenge: { [unowned self] reference in
                         try self.crash.tick()
                         // As the account manager: it keeps only what its
                         // resolver would answer for the credential.
                         let accepted = try self.launchStore.isManaged() && (reference != nil) == self.launchStore.hasPasscode()
                         guard accepted else {
                             if reference != nil { throw LocalAccessChallengeRejected() }
                             return
                         }
                         self.marker = nil
                         self.accessChallenges.append(reference)
                     })
    }

    /// As `LocalPasscode.legacyMarkerCode`: the account manager replaces the
    /// marker once the credential is managed.
    var legacyMarkerCode: String? {
        if (try? self.launchStore.isManaged()) == true {
            self.marker = nil
        }
        return self.marker
    }

    var legacyURL: URL { self.unlock.legacyKeyReader.encryptedURL }
    var plaintextURL: URL { self.unlock.legacyKeyReader.plaintextURL }
    var v2URL: URL { self.unlock.databaseKeyFile.url }

    func installLegacy(_ databaseKey: DatabaseKey, passcode: String?) {
        self.storage.files[self.legacyURL] = LegacyFile.encrypt(databaseKey, passcode: passcode)
    }

    /// What `LocalPasscode` does at launch: decide, then unlock with `code`
    /// if the lock asks for one.
    func launch(code: String?) throws -> DatabaseKey {
        let unlock = self.unlock
        switch try unlock.state() {
        case .legacy(needsPasscode: false):
            return try unlock.unlockLegacy(code: nil, settingPasscode: self.legacyMarkerCode)
        case .legacy(needsPasscode: true):
            return try unlock.unlockLegacy(code: code)
        case let .v2(needsPasscode):
            return try unlock.unlockV2(code: needsPasscode ? code : nil)
        case .fresh:
            return try unlock.createFresh()
        case .credentialLost:
            throw LaunchUnlockError.keyFileMissing
        }
    }

    /// Crashes `run` after each step in turn; `check` sees the world after
    /// the crash. Returns the number of steps that crashed.
    static func crashAtEachStep(realStore: Bool = false, setUp: (World) -> Void, run: (World) throws -> Void,
                                check: (World, Int) throws -> Void) throws -> Int {
        var step = 0
        while true {
            let world = World(realStore: realStore)
            setUp(world)
            world.crash.remaining = step
            do {
                try run(world)
                return step
            } catch is Crash {
            }
            try check(world, step)
            step += 1
        }
    }
}

private struct LocalAccessChallengeRejected: Error {}

final class LaunchUnlockTests: XCTestCase {
    private static let key = DatabaseKey.random()

    /// After an interrupted run, one more launch with `passcode` must
    /// leave a finished migration that keeps the passcode.
    private static func assertMigrated(_ world: World, passcode: String?, _ message: String) throws {
        XCTAssertEqual(try world.launch(code: passcode), self.key, message)
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: passcode != nil), message)
        XCTAssertEqual(try world.unlock.legacyKeyReader.state(), .retired, message)
        XCTAssertEqual(try world.unlock.unlockV2(code: passcode), self.key, message)
        XCTAssertEqual(try world.launchStore.isProtectionEnabled(), passcode != nil, message)
        XCTAssertEqual(world.accessChallenges.last.map { $0 != nil }, passcode != nil, message)
    }

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
        XCTAssertEqual(world.store.credential?.managed, true)
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

    func testMigratesFilesWrittenByOldCode() throws {
        for fixture in LegacyFixture.all {
            let world = World()
            world.storage.files[world.legacyURL] = Data(hex: fixture.file)
            let hasPasscode = fixture.passcode != nil
            XCTAssertEqual(try world.unlock.state(), .legacy(needsPasscode: hasPasscode))
            if hasPasscode {
                XCTAssertThrowsError(try world.unlock.unlockLegacy(code: "0000"))
                XCTAssertNil(world.store.credential)
            }

            XCTAssertEqual(try world.launch(code: fixture.passcode), fixture.databaseKey)
            XCTAssertEqual(world.store.credential?.protectionEnabled, hasPasscode)
            XCTAssertEqual(try world.unlock.legacyKeyReader.state(), .retired)
            XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: hasPasscode))
            XCTAssertEqual(try world.unlock.unlockV2(code: fixture.passcode), fixture.databaseKey)
        }
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
        for realStore in [false, true] {
            for passcode in (realStore ? ["1234", nil] : ["1234", "pass word", nil]) as [String?] {
                let steps = try World.crashAtEachStep(realStore: realStore, setUp: { _ in }, run: { world in
                    world.installLegacy(Self.key, passcode: passcode)
                    _ = try world.launch(code: passcode)
                }, check: { world, step in
                    // The next launch, with the same code, finishes the job.
                    try Self.assertMigrated(world, passcode: passcode, "real \(realStore) step \(step)")
                })
                XCTAssertGreaterThanOrEqual(steps, passcode == nil ? 4 : 6, "\(String(describing: passcode))")
            }
        }
    }

    func testMigrationOverStaleCredentialInterruptedAfterEachStepResumes() throws {
        let steps = try World.crashAtEachStep(setUp: { world in
            world.store.credential = .init(code: "0000", kind: .digits4, protectionEnabled: true, managed: true)
            world.installLegacy(Self.key, passcode: "1234")
        }, run: { world in
            _ = try world.launch(code: "1234")
        }, check: { world, step in
            try Self.assertMigrated(world, passcode: "1234", "step \(step)")
        })
        XCTAssertGreaterThanOrEqual(steps, 8)
    }

    func testMarkerMigrationInterruptedAfterEachStepKeepsThePasscode() throws {
        for realStore in [false, true] {
            let steps = try World.crashAtEachStep(realStore: realStore, setUp: { world in
                world.installLegacy(Self.key, passcode: nil)
                world.marker = "123456"
            }, run: { world in
                _ = try world.launch(code: nil)
            }, check: { world, step in
                // Once the marker is gone the lock asks; the user types it.
                try Self.assertMigrated(world, passcode: "123456", "real \(realStore) step \(step)")
            })
            XCTAssertGreaterThanOrEqual(steps, 6)
        }
    }

    func testInterruptedMarkerMigrationRejectsAnotherCode() throws {
        let world = World()
        world.installLegacy(Self.key, passcode: nil)
        world.marker = "123456"
        // Dies right after the account manager recorded the credential.
        world.crash.remaining = 5
        XCTAssertThrowsError(try world.launch(code: nil)) { XCTAssertTrue($0 is Crash) }
        XCTAssertNil(world.legacyMarkerCode)
        XCTAssertEqual(try world.unlock.state(), .legacy(needsPasscode: true))
        XCTAssertThrowsError(try world.launch(code: "000000")) {
            XCTAssertEqual($0 as? PasscodeError, .invalidCode)
        }
        XCTAssertThrowsError(try world.launch(code: nil))
        XCTAssertFalse(world.store.calls.contains("resetCredential"))
        try Self.assertMigrated(world, passcode: "123456", "")
    }

    func testFreshInstallInterruptedResumes() throws {
        let steps = try World.crashAtEachStep(setUp: { _ in }, run: { world in
            _ = try world.launch(code: nil)
        }, check: { world, step in
            let databaseKey = try world.launch(code: nil)
            XCTAssertEqual(try world.launch(code: nil), databaseKey, "step \(step)")
            XCTAssertEqual(try world.unlock.legacyKeyReader.state(), .retired, "step \(step)")
            XCTAssertEqual(world.accessChallenges.last, .some(nil), "step \(step)")
        })
        XCTAssertGreaterThanOrEqual(steps, 4)
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

    func testLeftoverPasscodeIsAskedForOverPasscodelessLegacyFile() throws {
        let world = World()
        world.store.credential = .init(code: "0000", kind: .digits4, protectionEnabled: true, managed: true)
        world.installLegacy(Self.key, passcode: nil)
        XCTAssertEqual(try world.unlock.state(), .legacy(needsPasscode: true))
        XCTAssertThrowsError(try world.launch(code: nil))
        XCTAssertThrowsError(try world.launch(code: "1111"))
        XCTAssertEqual(world.store.credential?.code, "0000")
        try Self.assertMigrated(world, passcode: "0000", "")
    }

    func testMigrationWithoutPasscodeManagesTheCredential() throws {
        // An unmanaged record would keep `.none` out of the account manager.
        let world = World()
        world.store.credential = .init()
        world.installLegacy(Self.key, passcode: nil)
        XCTAssertEqual(try world.launch(code: nil), Self.key)
        XCTAssertEqual(world.store.credential?.managed, true)
        XCTAssertEqual(world.accessChallenges, [nil])
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

    func testResetKeepingDatabaseKeyKeepsTheRunningKey() throws {
        let world = World()
        world.installLegacy(Self.key, passcode: "1234")
        _ = try world.launch(code: "1234")
        try world.unlock.resetCredential(keeping: Self.key)
        XCTAssertEqual(world.store.credential?.code, nil)
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: false))
        XCTAssertEqual(try world.unlock.unlockV2(code: nil), Self.key)
        XCTAssertEqual(try world.unlock.legacyKeyReader.state(), .retired)
        XCTAssertEqual(world.accessChallenges.last, .some(nil))
    }

    func testResetKeepingDatabaseKeyInterruptedNeverStartsFresh() throws {
        let steps = try World.crashAtEachStep(setUp: { world in
            world.installLegacy(Self.key, passcode: "1234")
            _ = try? world.launch(code: "1234")
        }, run: { world in
            try world.unlock.resetCredential(keeping: Self.key)
        }, check: { world, step in
            XCTAssertNotNil(world.storage.files[world.v2URL], "step \(step)")
            XCTAssertNotEqual(try world.unlock.state(), .fresh, "step \(step)")
            XCTAssertThrowsError(try world.unlock.createFresh(), "step \(step)")
            // Either the key still opens, or the launch fails visibly.
            if let databaseKey = try? world.launch(code: "1234") {
                XCTAssertEqual(databaseKey, Self.key, "step \(step)")
            }
        })
        XCTAssertGreaterThanOrEqual(steps, 3)
    }

    func testBiometricsSettingIsReadFromTheStore() throws {
        let world = World()
        world.installLegacy(Self.key, passcode: "1234")
        _ = try world.launch(code: "1234")
        XCTAssertFalse(try world.unlock.isBiometricsEnabled())
        world.store.credential?.biometricsEnabled = true
        XCTAssertTrue(try world.unlock.isBiometricsEnabled())
    }

    func testBiometricUnlockOpensTheSameKey() throws {
        let world = World()
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: "1234")
        _ = try world.launch(code: "1234")
        world.store.credential?.biometricsEnabled = true
        let writes = world.storage.writes
        XCTAssertEqual(try world.unlock.unlockV2(biometrics: LAContext()), databaseKey)
        XCTAssertEqual(world.storage.writes, writes)
    }

    func testCancelledBiometricUnlockLeavesTheCodeWorking() throws {
        let world = World()
        let databaseKey = DatabaseKey.random()
        world.installLegacy(databaseKey, passcode: "1234")
        _ = try world.launch(code: "1234")
        world.store.credential?.biometricsEnabled = true
        world.store.biometricFailure = .cancelled
        XCTAssertThrowsError(try world.unlock.unlockV2(biometrics: LAContext())) {
            XCTAssertEqual($0 as? PasscodeError, .cancelled)
        }
        XCTAssertEqual(try world.unlock.state(), .v2(needsPasscode: true))
        XCTAssertEqual(try world.unlock.unlockV2(code: "1234"), databaseKey)
    }

    func testBiometricUnlockWithoutBiometricsFails() throws {
        let world = World()
        world.installLegacy(DatabaseKey.random(), passcode: "1234")
        _ = try world.launch(code: "1234")
        XCTAssertThrowsError(try world.unlock.unlockV2(biometrics: LAContext())) {
            XCTAssertEqual($0 as? PasscodeError, .biometricsUnavailable)
        }
    }
}
