import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
@testable import PasscodeCore
@testable import MacPasscode

struct Crash: Error {}

/// Throws `Crash` on the n-th state-changing operation, to simulate the
/// process dying between two steps.
final class CrashPoint {
    var remaining: Int?

    func tick() throws {
        guard let remaining else { return }
        if remaining == 0 {
            self.remaining = nil
            throw Crash()
        }
        self.remaining = remaining - 1
    }
}

final class InMemoryStorage: KeyFileStorage {
    var files: [URL: Data] = [:]
    var unreadable: Set<URL> = []
    var writes: [URL] = []
    var corruptWrites = false
    let crash: CrashPoint

    init(crash: CrashPoint = CrashPoint()) {
        self.crash = crash
    }

    func read(_ url: URL) throws -> Data? {
        if self.unreadable.contains(url) { throw CocoaError(.fileReadNoPermission) }
        return self.files[url]
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        try self.crash.tick()
        self.writes.append(url)
        self.files[url] = self.corruptWrites ? Data(repeating: 1, count: data.count) : data
    }

    func remove(_ url: URL) throws {
        try self.crash.tick()
        self.writes.append(url)
        self.files[url] = nil
    }
}

/// Mirrors the parts of `PasscodeCredentialStore` launch relies on: the
/// access key survives migrate / protect, and only a reset replaces it.
final class FakeCredentialStore: LaunchCredentialStore {
    struct Credential {
        var id = UUID().uuidString
        var accessKey = SymmetricKey(size: .bits256)
        var code: String?
        var kind: PasscodeKind?
        var protectionEnabled = false
        /// Set by `migrateLegacy` and resets, as PasscodeCore's
        /// `managedPasscode`; a managed credential is never migrated again.
        var managed = false
        var biometricsEnabled = false
    }

    var credential: Credential?
    var calls: [String] = []
    var failure: PasscodeError?
    /// What the Touch ID prompt answers, e.g. `.cancelled`; nil = success.
    var biometricFailure: PasscodeError?
    /// What a passcode check throws, e.g. `.cooldown`; nil = check normally.
    var sealingKeyFailure: PasscodeError?
    let crash: CrashPoint

    init(crash: CrashPoint = CrashPoint()) {
        self.crash = crash
    }

    private func enter(_ name: String) throws {
        if let failure { throw failure }
        try self.crash.tick()
        self.calls.append(name)
    }

    var reference: PasscodeCredentialReference? {
        guard let credential, let kind = credential.kind else { return nil }
        return PasscodeCredentialReference(id: credential.id, kind: kind)
    }

    func hasStoredCredential() throws -> Bool {
        if let failure { throw failure }
        return self.credential != nil
    }

    func isProtectionEnabled() throws -> Bool {
        if let failure { throw failure }
        return self.credential?.protectionEnabled ?? false
    }

    func migrateLegacy(code: String, kind: PasscodeKind) throws -> PasscodeCredentialReference? {
        try self.enter("migrateLegacy")
        var credential = self.credential ?? Credential()
        if !credential.managed {
            credential.code = kind.normalize(code)
            credential.kind = kind
            credential.managed = true
        }
        self.credential = credential
        return self.reference
    }

    func setInitialPasscode(code: String, kind: PasscodeKind) throws -> PasscodeCredentialReference {
        try self.enter("setInitialPasscode")
        var credential = self.credential ?? Credential()
        guard credential.kind == nil else { throw PasscodeError.authenticationRequired }
        credential.code = kind.normalize(code)
        credential.kind = kind
        credential.protectionEnabled = true
        credential.managed = true
        self.credential = credential
        return self.reference!
    }

    func enableProtection(code: String) throws {
        try self.enter("enableProtection")
        try self.check(code)
        self.credential?.protectionEnabled = true
    }

    func hasPasscode() throws -> Bool {
        if let failure { throw failure }
        return self.credential?.kind != nil
    }

    func isManaged() throws -> Bool {
        if let failure { throw failure }
        return self.credential?.managed ?? false
    }

    func databaseSealingKey(code: String?) throws -> SymmetricKey {
        try self.enter("databaseSealingKey")
        if let sealingKeyFailure { throw sealingKeyFailure }
        if let code {
            try self.check(code)
        } else {
            if self.credential == nil { self.credential = Credential() }
            if self.credential!.protectionEnabled { throw PasscodeError.authenticationRequired }
        }
        return self.credential!.accessKey
    }

    func isBiometricsEnabled() throws -> Bool {
        if let failure { throw failure }
        return self.credential?.biometricsEnabled ?? false
    }

    func biometricDatabaseSealingKey(context: LAContext) throws -> SymmetricKey {
        try self.enter("biometricDatabaseSealingKey")
        if let biometricFailure { throw biometricFailure }
        guard let credential, credential.protectionEnabled, credential.biometricsEnabled else {
            throw PasscodeError.biometricsUnavailable
        }
        return credential.accessKey
    }

    func resetCredential(removingProtectedData: () throws -> Void) throws {
        try self.enter("resetCredential")
        try removingProtectedData()
        self.credential = Credential(managed: true)
    }

    private func check(_ code: String) throws {
        guard let credential, let kind = credential.kind, credential.code == kind.normalize(code) else {
            throw PasscodeError.invalidCode
        }
    }
}

enum LegacyFile {
    /// The old `reencrypt`: key + salt + murmur hash, zero padded, then
    /// AES-CBC under SHA-512(passcode). Checked byte for byte against
    /// files written by `BuildConfig.m` in `LegacyKeyFileTests`.
    static func encrypt(_ databaseKey: DatabaseKey, passcode: String?) -> Data {
        var hash = LegacyKeyFile.murmurHash32(databaseKey.bytes).littleEndian
        var plaintext = databaseKey.bytes + Data(bytes: &hash, count: 4)
        plaintext += Data(count: (16 - plaintext.count % 16) % 16)
        return self.aesCBCEncrypt(plaintext, passcode: passcode ?? LegacyKeyFile.defaultPasscode)
    }

    private static func aesCBCEncrypt(_ data: Data, passcode: String) -> Data {
        let digest = Data(SHA512.hash(data: Data(passcode.utf8)))
        let key = digest.prefix(32)
        let iv = digest.suffix(16)
        var output = Data(count: data.count)
        var processed = 0
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), 0,
                                key.baseAddress, key.count, iv.baseAddress,
                                input.baseAddress, input.count, out.baseAddress, out.count, &processed)
                    }
                }
            }
        }
        precondition(status == kCCSuccess && processed == data.count)
        return output
    }
}

/// PasscodeCore's keychain items, kept in memory.
final class InMemoryPasscodeStorage: PasscodeStorage {
    var items: [String: Data] = [:]

    func read(_ account: String, context: LAContext?) throws -> Data? {
        self.items[account]
    }

    func write(_ data: Data, account: String, biometric: Bool) throws {
        self.items[account] = data
    }

    func remove(_ account: String) throws {
        self.items[account] = nil
    }
}

extension CoreLaunchCredentialStore {
    /// The real PasscodeCore store over in-memory items, with the fewest
    /// key derivation rounds PasscodeCore accepts.
    static func inMemory() -> CoreLaunchCredentialStore {
        PasscodeSession.setApplicationAvailable(true)
        return CoreLaunchCredentialStore(store: PasscodeCredentialStore(storage: InMemoryPasscodeStorage(),
                                                                        iterations: { PasscodeCrypto.minimumIterations }))
    }
}

/// Throws `Crash` before each state-changing call to `base`.
final class CrashingCredentialStore: LaunchCredentialStore {
    private let base: LaunchCredentialStore
    private let crash: CrashPoint

    init(_ base: LaunchCredentialStore, crash: CrashPoint) {
        self.base = base
        self.crash = crash
    }

    func hasStoredCredential() throws -> Bool { try self.base.hasStoredCredential() }
    func isProtectionEnabled() throws -> Bool { try self.base.isProtectionEnabled() }
    func hasPasscode() throws -> Bool { try self.base.hasPasscode() }
    func isManaged() throws -> Bool { try self.base.isManaged() }
    func isBiometricsEnabled() throws -> Bool { try self.base.isBiometricsEnabled() }

    func migrateLegacy(code: String, kind: PasscodeKind) throws -> PasscodeCredentialReference? {
        try self.crash.tick()
        return try self.base.migrateLegacy(code: code, kind: kind)
    }

    func setInitialPasscode(code: String, kind: PasscodeKind) throws -> PasscodeCredentialReference {
        try self.crash.tick()
        return try self.base.setInitialPasscode(code: code, kind: kind)
    }

    func enableProtection(code: String) throws {
        try self.crash.tick()
        try self.base.enableProtection(code: code)
    }

    func databaseSealingKey(code: String?) throws -> SymmetricKey {
        try self.crash.tick()
        return try self.base.databaseSealingKey(code: code)
    }

    func biometricDatabaseSealingKey(context: LAContext) throws -> SymmetricKey {
        try self.crash.tick()
        return try self.base.biometricDatabaseSealingKey(context: context)
    }

    func resetCredential(removingProtectedData: () throws -> Void) throws {
        try self.crash.tick()
        try self.base.resetCredential(removingProtectedData: removingProtectedData)
    }
}

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index ..< next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
