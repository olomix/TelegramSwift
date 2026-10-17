import CryptoKit
import Foundation
import LocalAuthentication
import PasscodeCore

/// The credential operations launch needs, implemented over
/// `PasscodeCredentialStore` by the app and by fakes in tests.
public protocol LaunchCredentialStore: CredentialReader {
    /// Idempotent: returns the existing reference once a code is migrated.
    func migrateLegacy(code: String, kind: PasscodeKind) throws -> PasscodeCredentialReference?
    /// Sets a passcode on a credential that has none; protection turns on.
    func setInitialPasscode(code: String, kind: PasscodeKind) throws -> PasscodeCredentialReference
    /// Verifies `code` and turns protection on; idempotent.
    func enableProtection(code: String) throws
    func isBiometricsEnabled() throws -> Bool
    /// As `databaseSealingKey(code:)`, through Touch ID; prompts with
    /// `context` and blocks until the user answers.
    func biometricDatabaseSealingKey(context: LAContext) throws -> SymmetricKey
    /// Runs `removingProtectedData`, then replaces the credential with a new
    /// unprotected one. Must not touch key files or databases itself.
    func resetCredential(removingProtectedData: () throws -> Void) throws
}

public enum LaunchState: Equatable {
    /// `db-key.v2` and its credential exist.
    case v2(needsPasscode: Bool)
    /// The old key file is still live; unlock it, then migrate.
    case legacy(needsPasscode: Bool)
    /// No key material at all.
    case fresh
    /// Key material exists but the credential that opens it is gone.
    case credentialLost
}

public enum LaunchUnlockError: Error, Equatable {
    case invalidCode
    case keyFileMissing
    case keyFileExists
}

/// Launch decisions and the legacy migration. Every step is idempotent and
/// the old key file stays live until `db-key.v2` is written and verified,
/// so an interrupted launch is finished by the next one.
public struct LaunchUnlock {
    public let databaseKeyFile: DatabaseKeyFile
    public let legacyKeyReader: LegacyKeyReader
    private let store: LaunchCredentialStore
    private let storeAccessChallenge: (PasscodeCredentialReference?) throws -> Void

    /// `storeAccessChallenge` records the passcode state in the account
    /// manager (`.secured` for a reference, `.none` for nil).
    public init(databaseKeyFile: DatabaseKeyFile,
                legacyKeyReader: LegacyKeyReader,
                store: LaunchCredentialStore,
                storeAccessChallenge: @escaping (PasscodeCredentialReference?) throws -> Void) {
        self.databaseKeyFile = databaseKeyFile
        self.legacyKeyReader = legacyKeyReader
        self.store = store
        self.storeAccessChallenge = storeAccessChallenge
    }

    /// Throws when a key file exists but cannot be read, or the store fails;
    /// neither is ever reported as `.fresh`.
    public func state() throws -> LaunchState {
        let legacy = try self.legacyKeyReader.state()
        let v2 = try self.databaseKeyFile.contents()
        switch legacy {
        case let .present(needsPasscode):
            return .legacy(needsPasscode: needsPasscode)
        case .retired:
            guard v2 != nil else { return .credentialLost }
        case .missing:
            guard v2 != nil else { return .fresh }
        }
        guard try self.store.hasStoredCredential() else { return .credentialLost }
        return .v2(needsPasscode: try self.store.isProtectionEnabled())
    }

    /// Opens `db-key.v2`; `code` is nil when protection is off.
    public func unlockV2(code: String?) throws -> DatabaseKey {
        let sealingKey = try self.store.databaseSealingKey(code: code)
        guard let databaseKey = try self.databaseKeyFile.read(with: sealingKey) else {
            throw LaunchUnlockError.keyFileMissing
        }
        return databaseKey
    }

    /// Whether the launch lock may offer Touch ID. Only `db-key.v2` behind a
    /// passcode qualifies: the old key file needs the code to migrate.
    public func offersBiometrics() throws -> Bool {
        guard try self.state() == .v2(needsPasscode: true) else { return false }
        return try self.store.isBiometricsEnabled()
    }

    /// Opens `db-key.v2` through Touch ID. A cancelled prompt throws
    /// `PasscodeError.cancelled` and changes nothing.
    public func unlockV2(biometrics context: LAContext) throws -> DatabaseKey {
        let sealingKey = try self.store.biometricDatabaseSealingKey(context: context)
        guard let databaseKey = try self.databaseKeyFile.read(with: sealingKey) else {
            throw LaunchUnlockError.keyFileMissing
        }
        return databaseKey
    }

    /// Opens the old key file with `code` (nil = no passcode set), then
    /// migrates it. A wrong code throws `.invalidCode` and changes nothing.
    public func unlockLegacy(code: String?) throws -> DatabaseKey {
        try self.unlockLegacy(code: code, settingPasscode: code)
    }

    /// As `unlockLegacy(code:)`, but migrates with `passcode` instead: an old
    /// account-manager marker could hold a code the key file never used.
    public func unlockLegacy(code: String?, settingPasscode passcode: String?) throws -> DatabaseKey {
        guard let databaseKey = try self.legacyKeyReader.read(passcode: code) else {
            throw LaunchUnlockError.invalidCode
        }
        try self.migrate(databaseKey, code: passcode)
        return databaseKey
    }

    /// Creates and stores a new database key; refuses when any key file
    /// exists.
    public func createFresh() throws -> DatabaseKey {
        guard try self.legacyKeyReader.state() == .missing, try self.databaseKeyFile.contents() == nil else {
            throw LaunchUnlockError.keyFileExists
        }
        // Leftover items of a deleted container would block the unprotected
        // session; with no key files there is nothing they could open.
        if try self.store.isProtectionEnabled() {
            try self.store.resetCredential(removingProtectedData: {})
        }
        let databaseKey = DatabaseKey.random()
        try self.storeUnprotected(databaseKey)
        return databaseKey
    }

    /// Deletes every key file, then runs `removingData` (the databases), then
    /// replaces the credential. Afterwards the next launch starts fresh.
    public func resetLocalSecrets(removingData: () throws -> Void) throws {
        try self.store.resetCredential(removingProtectedData: {
            try self.databaseKeyFile.remove()
            try self.legacyKeyReader.remove()
            try removingData()
        })
    }

    /// Seals a key that is still in use under the credential a reset left,
    /// so the running app's databases stay readable after the next launch.
    /// Refuses to overwrite an existing `db-key.v2`.
    public func sealAfterReset(_ databaseKey: DatabaseKey) throws {
        guard try self.databaseKeyFile.contents() == nil else {
            throw LaunchUnlockError.keyFileExists
        }
        try self.storeUnprotected(databaseKey)
    }

    private func storeUnprotected(_ databaseKey: DatabaseKey) throws {
        try self.databaseKeyFile.write(databaseKey, with: try self.store.databaseSealingKey(code: nil))
        // An older build or extension creates a new key file when none
        // exists; a later launch would then migrate that wrong key.
        try self.legacyKeyReader.retire()
        try self.storeAccessChallenge(nil)
    }

    private func migrate(_ databaseKey: DatabaseKey, code: String?) throws {
        var reference: PasscodeCredentialReference?
        if let code {
            do {
                reference = try self.adoptLegacyPasscode(code)
            } catch PasscodeError.invalidCode {
                // A credential left by an earlier install holds another code.
                // The live legacy file still has the key, so dropping it is safe.
                try self.store.resetCredential(removingProtectedData: {})
                reference = try self.adoptLegacyPasscode(code)
            }
        } else if try self.store.isProtectionEnabled() {
            try self.store.resetCredential(removingProtectedData: {})
        }
        try self.databaseKeyFile.write(databaseKey, with: try self.store.databaseSealingKey(code: code))
        try self.storeAccessChallenge(reference)
        try self.legacyKeyReader.retire()
    }

    private func adoptLegacyPasscode(_ code: String) throws -> PasscodeCredentialReference {
        let kind = PasscodeKindMapping.kind(for: code)
        // A reset credential counts as migrated, with no passcode.
        let reference = try self.store.migrateLegacy(code: code, kind: kind)
            ?? self.store.setInitialPasscode(code: code, kind: kind)
        try self.store.enableProtection(code: code)
        return reference
    }
}
