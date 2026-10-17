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
    /// Whether the credential holds a passcode, protected or not yet.
    func hasPasscode() throws -> Bool
    /// Whether the credential was migrated or reset, as PasscodeCore's
    /// `managedReference()`; the account manager stores `.none` only then.
    func isManaged() throws -> Bool
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
    public let legacyKeyFile: LegacyKeyFile
    private let store: LaunchCredentialStore
    private let storeAccessChallenge: (PasscodeCredentialReference?) throws -> Void

    /// `storeAccessChallenge` records the passcode state in the account
    /// manager (`.secured` for a reference, `.none` for nil).
    public init(databaseKeyFile: DatabaseKeyFile,
                legacyKeyFile: LegacyKeyFile,
                store: LaunchCredentialStore,
                storeAccessChallenge: @escaping (PasscodeCredentialReference?) throws -> Void) {
        self.databaseKeyFile = databaseKeyFile
        self.legacyKeyFile = legacyKeyFile
        self.store = store
        self.storeAccessChallenge = storeAccessChallenge
    }

    /// Throws when a key file exists but cannot be read, or the store fails;
    /// neither is ever reported as `.fresh`.
    public func state() throws -> LaunchState {
        let legacy = try self.legacyKeyFile.state()
        let v2 = try self.databaseKeyFile.contents()
        switch legacy {
        case let .present(needsPasscode):
            // An interrupted migration of an old marker's code leaves that code
            // in the credential only; the key file never had it.
            return .legacy(needsPasscode: try needsPasscode || self.store.hasPasscode())
        case .retired:
            guard v2 != nil else { return .credentialLost }
        case .missing:
            guard v2 != nil else { return .fresh }
        }
        guard try self.store.hasStoredCredential() else { return .credentialLost }
        return .v2(needsPasscode: try self.store.isProtectionEnabled())
    }

    /// Whether the account manager must keep an old passcode marker as is:
    /// until the live old key file is migrated it may hold the only copy.
    /// False once the user forgot the passcode, so the marker is dropped.
    public func keepsLegacyMarker() throws -> Bool {
        guard case .present = try self.legacyKeyFile.state() else { return false }
        return try !self.legacyKeyFile.isPasscodeForgotten()
    }

    /// Opens `db-key.v2`; `code` is nil when protection is off.
    public func unlockV2(code: String?) throws -> DatabaseKey {
        try self.openV2(with: self.store.databaseSealingKey(code: code))
    }

    /// Whether the launch lock may offer Touch ID for `.v2(needsPasscode:
    /// true)`; the old key file needs the code to migrate.
    public func isBiometricsEnabled() throws -> Bool {
        try self.store.isBiometricsEnabled()
    }

    /// Opens `db-key.v2` through Touch ID. A cancelled prompt throws
    /// `PasscodeError.cancelled` and changes nothing.
    public func unlockV2(biometrics context: LAContext) throws -> DatabaseKey {
        try self.openV2(with: self.store.biometricDatabaseSealingKey(context: context))
    }

    private func openV2(with sealingKey: SymmetricKey) throws -> DatabaseKey {
        guard let databaseKey = try self.databaseKeyFile.read(with: sealingKey) else {
            throw LaunchUnlockError.keyFileMissing
        }
        try self.finishInterruptedStore()
        return databaseKey
    }

    /// A crash right after `db-key.v2` was written leaves no old key file;
    /// an older build or extension would then create a new key there.
    private func finishInterruptedStore() throws {
        guard try self.legacyKeyFile.state() == .missing else { return }
        if try !self.store.isProtectionEnabled() {
            try self.storeAccessChallenge(nil)
        }
        try self.legacyKeyFile.retire()
    }

    /// Opens the old key file with `code` (nil = none), migrates it with
    /// `settingPasscode ?? code`: an old marker's code may differ from it.
    public func unlockLegacy(code: String?, settingPasscode: String? = nil) throws -> DatabaseKey {
        if let databaseKey = try self.legacyKeyFile.read(passcode: code) {
            let markerCode = try self.legacyKeyFile.isPasscodeForgotten() ? nil : settingPasscode
            try self.migrate(databaseKey, code: markerCode ?? code, replacingStaleCredential: true)
            return databaseKey
        }
        // Resuming a marker migration: only the credential can check `code`.
        guard let code, try self.store.hasPasscode(),
              let databaseKey = try self.legacyKeyFile.read(passcode: nil) else {
            throw LaunchUnlockError.invalidCode
        }
        try self.migrate(databaseKey, code: code, replacingStaleCredential: false)
        return databaseKey
    }

    /// Whether the lock may offer `forgetPasscode()`: the live old key file
    /// opens without a passcode, so only the credential asks for one.
    public func canForgetPasscode() throws -> Bool {
        try self.passcodelessLegacyKey() != nil && self.store.hasPasscode()
    }

    /// Drops the credential's passcode and migrates the old key file without
    /// one, keeping the data. Throws `.invalidCode` unless the old key file
    /// is live and opens without a passcode.
    public func forgetPasscode() throws -> DatabaseKey {
        guard let databaseKey = try self.passcodelessLegacyKey() else {
            throw LaunchUnlockError.invalidCode
        }
        // Recorded first: after the reset the old marker alone would look
        // like a passcode still to migrate.
        try self.legacyKeyFile.markPasscodeForgotten()
        if try self.store.hasPasscode() {
            try self.store.resetCredential(removingProtectedData: {})
        }
        try self.migrate(databaseKey, code: nil, replacingStaleCredential: false)
        return databaseKey
    }

    private func passcodelessLegacyKey() throws -> DatabaseKey? {
        guard try self.legacyKeyFile.state() == .present(needsPasscode: false) else {
            return nil
        }
        return try self.legacyKeyFile.read(passcode: nil)
    }

    /// Creates and stores a new database key; refuses when any key file
    /// exists.
    public func createFresh() throws -> DatabaseKey {
        guard try self.legacyKeyFile.state() == .missing, try self.databaseKeyFile.contents() == nil else {
            throw LaunchUnlockError.keyFileExists
        }
        // Leftover items of a deleted container would block the unprotected
        // session or `.none`; with no key files they open nothing.
        if try self.store.hasPasscode() || !self.store.isManaged() {
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
            try self.legacyKeyFile.remove()
            try removingData()
        })
    }

    /// Replaces the credential with an unprotected one sealing `databaseKey`.
    /// Overwrites key files, never deletes, so a failure is no fresh start.
    public func resetCredential(keeping databaseKey: DatabaseKey) throws {
        try self.store.resetCredential(removingProtectedData: {})
        try self.storeUnprotected(databaseKey)
    }

    private func storeUnprotected(_ databaseKey: DatabaseKey) throws {
        try self.databaseKeyFile.write(databaseKey, with: try self.store.databaseSealingKey(code: nil))
        try self.storeAccessChallenge(nil)
        // An older build or extension creates a new key file when none
        // exists; a later launch would then migrate that wrong key.
        try self.legacyKeyFile.retire()
    }

    /// `replacingStaleCredential` is false when only the credential vouches
    /// for `code`; resetting it then would accept any code.
    private func migrate(_ databaseKey: DatabaseKey, code: String?, replacingStaleCredential: Bool) throws {
        var reference: PasscodeCredentialReference?
        if let code {
            do {
                reference = try self.adoptLegacyPasscode(code)
            } catch PasscodeError.invalidCode where replacingStaleCredential {
                // A credential left by an earlier install holds another code.
                // The live legacy file still has the key, so dropping it is safe.
                try self.store.resetCredential(removingProtectedData: {})
                reference = try self.adoptLegacyPasscode(code)
            }
        } else {
            guard try !self.store.hasPasscode() else {
                throw LaunchUnlockError.invalidCode
            }
            if try !self.store.isManaged() {
                try self.store.resetCredential(removingProtectedData: {})
            }
        }
        try self.databaseKeyFile.write(databaseKey, with: try self.store.databaseSealingKey(code: code))
        try self.storeAccessChallenge(reference)
        try self.legacyKeyFile.retire()
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
