import CommonCrypto
import CryptoKit
import Foundation

/// Reads the database key stored by the old `AppEncryptionParameters`
/// (`submodules/BuildConfig/Sources/BuildConfig.m`) without its side
/// effects: reading never creates, upgrades or deletes a file.
///
/// `.tempkeyEncrypted` is AES-256-CBC without padding, keyed by
/// SHA-512(UTF-8 passcode) (key = first 32 bytes, IV = last 16), over
/// key(32) + salt(16) + murmur3-32(key + salt, little endian) + zero
/// padding. Without a passcode the old code used `defaultPasscode`. A
/// 48-byte plaintext `.tempkey` overrides it, as the old init did.
public struct LegacyKeyReader {
    public static let defaultPasscode = "no-matter-key"
    public static let encryptedFileName = ".tempkeyEncrypted"
    public static let plaintextFileName = ".tempkey"
    static let retiredMarker = Data("telex.legacy-key.retired".utf8)
    static let retiredLength = 64

    public enum State: Equatable {
        case missing
        /// Replaced by `retire()`; holds no key.
        case retired
        case present(needsPasscode: Bool)
    }

    public let encryptedURL: URL
    public let plaintextURL: URL
    private let storage: KeyFileStorage

    public init(directory: URL, storage: KeyFileStorage = LocalKeyFileStorage()) {
        self.encryptedURL = directory.appendingPathComponent(Self.encryptedFileName)
        self.plaintextURL = directory.appendingPathComponent(Self.plaintextFileName)
        self.storage = storage
    }

    /// Throws when a file exists but cannot be read.
    public func state() throws -> State {
        if try self.plaintextKey() != nil {
            return .present(needsPasscode: false)
        }
        guard let data = try self.storage.read(self.encryptedURL) else { return .missing }
        if Self.isRetired(data) { return .retired }
        return .present(needsPasscode: Self.decrypt(data, passcode: Self.defaultPasscode) == nil)
    }

    /// The key for `passcode` (nil = no passcode set). Returns nil when the
    /// files are missing or retired, or the passcode is wrong.
    public func read(passcode: String?) throws -> DatabaseKey? {
        if let key = try self.plaintextKey() {
            return passcode == nil ? key : nil
        }
        guard let data = try self.storage.read(self.encryptedURL), !Self.isRetired(data) else { return nil }
        return Self.decrypt(data, passcode: passcode ?? Self.defaultPasscode)
    }

    /// Overwrites `.tempkeyEncrypted` with bytes no passcode opens, then
    /// removes `.tempkey`. Not deleted: an older build would see a missing
    /// file, create a new key and lose the database; this way it shows its
    /// lock screen instead.
    public func retire() throws {
        var marker: Data
        repeat {
            marker = Self.retiredMarker + randomBytes(Self.retiredLength - Self.retiredMarker.count)
        } while Self.decrypt(marker, passcode: Self.defaultPasscode) != nil
        try self.storage.writeAtomically(marker, to: self.encryptedURL)
        try self.storage.remove(self.plaintextURL)
    }

    /// Deletes both files; only for a reset that drops the databases too.
    public func remove() throws {
        try self.storage.remove(self.encryptedURL)
        try self.storage.remove(self.plaintextURL)
    }

    private func plaintextKey() throws -> DatabaseKey? {
        guard let data = try self.storage.read(self.plaintextURL) else { return nil }
        return DatabaseKey(data)
    }

    static func isRetired(_ data: Data) -> Bool {
        data.count == retiredLength && data.starts(with: retiredMarker)
    }

    static func decrypt(_ data: Data, passcode: String) -> DatabaseKey? {
        guard let decrypted = aesCBC(decrypt: true, data, passcode: passcode),
              decrypted.count >= 32 + 16 + 4 else { return nil }
        let keyAndSalt = Data(decrypted.prefix(48))
        let storedHash = decrypted[decrypted.startIndex + 48 ..< decrypted.startIndex + 52]
            .reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard storedHash == murmurHash32(keyAndSalt) else { return nil }
        return DatabaseKey(keyAndSalt)
    }

    static func aesCBC(decrypt: Bool, _ data: Data, passcode: String) -> Data? {
        let digest = Data(SHA512.hash(data: Data(passcode.utf8)))
        let key = digest.prefix(32)
        let iv = digest.suffix(16)
        var output = Data(count: data.count)
        var processed = 0
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), 0,
                                key.baseAddress, key.count, iv.baseAddress,
                                input.baseAddress, input.count, out.baseAddress, out.count, &processed)
                    }
                }
            }
        }
        guard status == kCCSuccess, processed == data.count else { return nil }
        return output
    }

    /// MurmurHash3 x86_32 with the seed of `MurMurHash32.m`.
    static func murmurHash32(_ data: Data) -> UInt32 {
        let c1: UInt32 = 0xcc9e2d51
        let c2: UInt32 = 0x1b873593
        let bytes = [UInt8](data)
        var h1 = UInt32(bitPattern: -137723950)
        let blockCount = bytes.count / 4
        for block in 0 ..< blockCount {
            let i = block * 4
            var k1 = UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
            k1 = (k1 &* c1).rotatedLeft(15) &* c2
            h1 ^= k1
            h1 = h1.rotatedLeft(13) &* 5 &+ 0xe6546b64
        }
        let tail = bytes[(blockCount * 4)...]
        if !tail.isEmpty {
            var k1: UInt32 = 0
            for (shift, byte) in tail.enumerated() {
                k1 ^= UInt32(byte) << (8 * shift)
            }
            h1 ^= (k1 &* c1).rotatedLeft(15) &* c2
        }
        h1 ^= UInt32(bytes.count)
        h1 ^= h1 >> 16
        h1 = h1 &* 0x85ebca6b
        h1 ^= h1 >> 13
        h1 = h1 &* 0xc2b2ae35
        h1 ^= h1 >> 16
        return h1
    }
}

private extension UInt32 {
    func rotatedLeft(_ count: UInt32) -> UInt32 {
        self << count | self >> (32 - count)
    }
}
