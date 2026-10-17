import CryptoKit
import Foundation

/// The database key and salt (`DeviceSpecificEncryptionParameters`).
public struct DatabaseKey: Equatable {
    public static let keyLength = 32
    public static let saltLength = 16

    public let key: Data
    public let salt: Data

    public init?(key: Data, salt: Data) {
        guard key.count == Self.keyLength, salt.count == Self.saltLength else { return nil }
        self.key = key
        self.salt = salt
    }

    init?(_ bytes: Data) {
        guard bytes.count == Self.keyLength + Self.saltLength else { return nil }
        self.init(key: Data(bytes.prefix(Self.keyLength)), salt: Data(bytes.suffix(Self.saltLength)))
    }

    public static func random() -> DatabaseKey {
        DatabaseKey(randomBytes(keyLength + saltLength))!
    }

    var bytes: Data { self.key + self.salt }
}

func randomBytes(_ count: Int) -> Data {
    SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
}

public enum DatabaseKeyFileError: Error, Equatable {
    case truncated
    case unknownVersion(UInt8)
    case authenticationFailed
    case invalidPayload
    /// The file read back after a write did not hold the written key.
    case verificationFailed
}

/// `db-key.v2`: a version byte followed by an `AES.GCM` sealed box
/// (combined form) holding the database key and salt.
public struct DatabaseKeyFile {
    public static let fileName = "db-key.v2"
    static let version: UInt8 = 1
    static let associatedData = Data("telex.db-key.v2".utf8)
    static let sealedLength = 1 + 12 + DatabaseKey.keyLength + DatabaseKey.saltLength + 16

    public let url: URL
    private let storage: KeyFileStorage

    public init(directory: URL, storage: KeyFileStorage = LocalKeyFileStorage()) {
        self.url = directory.appendingPathComponent(Self.fileName)
        self.storage = storage
    }

    /// The raw file, nil when it does not exist.
    public func contents() throws -> Data? {
        try self.storage.read(self.url)
    }

    /// The stored key, nil when the file does not exist.
    public func read(with sealingKey: SymmetricKey) throws -> DatabaseKey? {
        guard let data = try self.contents() else { return nil }
        return try Self.unseal(data, with: sealingKey)
    }

    /// Writes atomically, then reads the file back and opens it, so a
    /// caller may retire older key material only after this returns.
    public func write(_ databaseKey: DatabaseKey, with sealingKey: SymmetricKey) throws {
        try self.storage.writeAtomically(try Self.seal(databaseKey, with: sealingKey), to: self.url)
        guard try self.read(with: sealingKey) == databaseKey else {
            throw DatabaseKeyFileError.verificationFailed
        }
    }

    public func remove() throws {
        try self.storage.remove(self.url)
    }

    public static func seal(_ databaseKey: DatabaseKey, with sealingKey: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(databaseKey.bytes, using: sealingKey, authenticating: associatedData)
        guard let combined = box.combined else { throw DatabaseKeyFileError.invalidPayload }
        return Data([version]) + combined
    }

    public static func unseal(_ data: Data, with sealingKey: SymmetricKey) throws -> DatabaseKey {
        guard let first = data.first else { throw DatabaseKeyFileError.truncated }
        guard first == version else { throw DatabaseKeyFileError.unknownVersion(first) }
        guard data.count >= sealedLength else { throw DatabaseKeyFileError.truncated }
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst())
            plaintext = try AES.GCM.open(box, using: sealingKey, authenticating: associatedData)
        } catch {
            throw DatabaseKeyFileError.authenticationFailed
        }
        guard let databaseKey = DatabaseKey(plaintext) else { throw DatabaseKeyFileError.invalidPayload }
        return databaseKey
    }
}
