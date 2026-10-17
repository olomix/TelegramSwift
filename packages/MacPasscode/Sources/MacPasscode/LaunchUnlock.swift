import CryptoKit
import Foundation
import PasscodeCore

/// The credential operations launch needs, implemented over
/// `PasscodeCredentialStore` by the app and by fakes in tests.
public protocol LaunchCredentialStore {
    func hasStoredCredential() throws -> Bool
    func isProtectionEnabled() throws -> Bool
    /// Idempotent: returns the existing reference once a code is migrated.
    func migrateLegacy(code: String, kind: PasscodeKind) throws -> PasscodeCredentialReference?
    /// Verifies `code` and turns protection on; idempotent.
    func enableProtection(code: String) throws
    /// The key that seals `db-key.v2`: derived through a session verified
    /// with `code`, or through the unprotected session when `code` is nil.
    func databaseSealingKey(code: String?) throws -> SymmetricKey
    /// Replaces the credential with a new unprotected one. Must not touch
    /// key files or databases.
    func resetCredential() throws
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
    case migrationFailed
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

    /// Opens the old key file with `code` (nil = no passcode set), then
    /// migrates it. A wrong code throws `.invalidCode` and changes nothing.
    public func unlockLegacy(code: String?) throws -> DatabaseKey {
        guard let databaseKey = try self.legacyKeyReader.read(passcode: code) else {
            throw LaunchUnlockError.invalidCode
        }
        try self.migrate(databaseKey, code: code)
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
            try self.store.resetCredential()
        }
        let databaseKey = DatabaseKey.random()
        try self.databaseKeyFile.write(databaseKey, with: try self.store.databaseSealingKey(code: nil))
        try self.storeAccessChallenge(nil)
        return databaseKey
    }

    private func migrate(_ databaseKey: DatabaseKey, code: String?) throws {
        var reference: PasscodeCredentialReference?
        if let code {
            reference = try self.store.migrateLegacy(code: code, kind: PasscodeKindMapping.kind(for: code))
            guard reference != nil else { throw LaunchUnlockError.migrationFailed }
            try self.store.enableProtection(code: code)
        }
        try self.databaseKeyFile.write(databaseKey, with: try self.store.databaseSealingKey(code: code))
        try self.storeAccessChallenge(reference)
        try self.legacyKeyReader.retire()
    }
}
