import CryptoKit
import Foundation

/// The credential reads needed to open `db-key.v2`. Nothing here migrates,
/// resets or sets a passcode.
public protocol CredentialReader {
    func hasStoredCredential() throws -> Bool
    func isProtectionEnabled() throws -> Bool
    /// The key that seals `db-key.v2`: derived through a session verified
    /// with `code`, or through the unprotected session when `code` is nil.
    func databaseSealingKey(code: String?) throws -> SymmetricKey
}

public enum ReadOnlyUnlockError: Error, Equatable {
    /// The old key file is still live, or no key exists yet: only the app
    /// may migrate or create one.
    case needsAppLaunch
    /// `db-key.v2` exists but the credential that opens it is gone.
    case credentialLost
    /// A key file write was attempted through `ReadOnlyUnlock`.
    case readOnly
}

/// Opens `db-key.v2` for a process that must not change local secrets: it
/// cannot migrate, write or retire key files, reset the credential or
/// create a database key. Writes through its storage throw `.readOnly`.
public struct ReadOnlyUnlock {
    public enum State: Equatable {
        case ready(needsPasscode: Bool)
        case needsAppLaunch
        case credentialLost
    }

    private let databaseKeyFile: DatabaseKeyFile
    private let legacyKeyReader: LegacyKeyReader
    private let credentials: CredentialReader

    public init(directory: URL, credentials: CredentialReader, storage: KeyFileStorage = LocalKeyFileStorage()) {
        let readOnlyStorage = ReadOnlyKeyFileStorage(storage)
        self.databaseKeyFile = DatabaseKeyFile(directory: directory, storage: readOnlyStorage)
        self.legacyKeyReader = LegacyKeyReader(directory: directory, storage: readOnlyStorage)
        self.credentials = credentials
    }

    /// Throws when a key file exists but cannot be read, or the store fails.
    public func state() throws -> State {
        let legacy = try self.legacyKeyReader.state()
        let v2 = try self.databaseKeyFile.contents()
        switch legacy {
        case .present:
            // Even next to `db-key.v2`: the app's migration is unfinished.
            return .needsAppLaunch
        case .retired:
            guard v2 != nil else { return .credentialLost }
        case .missing:
            guard v2 != nil else { return .needsAppLaunch }
        }
        guard try self.credentials.hasStoredCredential() else { return .credentialLost }
        return .ready(needsPasscode: try self.credentials.isProtectionEnabled())
    }

    /// Opens `db-key.v2`; `code` is ignored when protection is off. A wrong
    /// code throws `PasscodeError.invalidCode` and changes no file.
    public func unlock(code: String?) throws -> DatabaseKey {
        switch try self.state() {
        case .needsAppLaunch:
            throw ReadOnlyUnlockError.needsAppLaunch
        case .credentialLost:
            throw ReadOnlyUnlockError.credentialLost
        case let .ready(needsPasscode):
            let sealingKey = try self.credentials.databaseSealingKey(code: needsPasscode ? code : nil)
            guard let databaseKey = try self.databaseKeyFile.read(with: sealingKey) else {
                throw LaunchUnlockError.keyFileMissing
            }
            return databaseKey
        }
    }
}

/// Passes reads through and refuses every change.
struct ReadOnlyKeyFileStorage: KeyFileStorage {
    private let base: KeyFileStorage

    init(_ base: KeyFileStorage) {
        self.base = base
    }

    func read(_ url: URL) throws -> Data? {
        try self.base.read(url)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        throw ReadOnlyUnlockError.readOnly
    }

    func remove(_ url: URL) throws {
        throw ReadOnlyUnlockError.readOnly
    }
}
