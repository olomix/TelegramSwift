import CryptoKit
import LocalAuthentication
import PasscodeCore

/// `LaunchCredentialStore` over PasscodeCore's keychain-backed store.
@available(macOS 11.0, *)
public struct CoreLaunchCredentialStore: LaunchCredentialStore {
    public static let namespace = "telex.db"
    static let domain = "db-key.v2"

    private let store: PasscodeCredentialStore

    public init(store: PasscodeCredentialStore = .shared) {
        self.store = store
    }

    public func hasStoredCredential() throws -> Bool {
        try self.store.hasStoredCredential()
    }

    public func isProtectionEnabled() throws -> Bool {
        try self.store.protectionSettings().enabled
    }

    public func migrateLegacy(code: String, kind: PasscodeKind) throws -> PasscodeCredentialReference? {
        try self.store.migrateLegacy(code: code, kind: kind)
    }

    public func setInitialPasscode(code: String, kind: PasscodeKind) throws -> PasscodeCredentialReference {
        try self.store.setPasscode(code, kind: kind, session: nil)
    }

    public func enableProtection(code: String) throws {
        let session = try self.store.verify(code, scope: .settings)
        defer { session.invalidate() }
        try self.store.setProtectionEnabled(true, session: session)
    }

    public func hasPasscode() throws -> Bool {
        try self.store.protectionSettings().passcode != nil
    }

    public func isManaged() throws -> Bool {
        try self.store.managedReference() != nil
    }

    public func databaseSealingKey(code: String?) throws -> SymmetricKey {
        let session: PasscodeSession
        if let code {
            session = try self.store.verify(code, scope: .resource(namespace: Self.namespace))
        } else {
            session = try self.store.unprotectedSession(namespace: Self.namespace)
        }
        return try Self.sealingKey(session)
    }

    public func isBiometricsEnabled() throws -> Bool {
        try self.store.protectionSettings().biometricsEnabled
    }

    public func biometricDatabaseSealingKey(context: LAContext) throws -> SymmetricKey {
        try Self.sealingKey(self.store.authenticateBiometrics(context: context, scope: .resource(namespace: Self.namespace)))
    }

    private static func sealingKey(_ session: PasscodeSession) throws -> SymmetricKey {
        defer { session.invalidate() }
        return try session.withDerivedKey(namespace: Self.namespace, domain: Self.domain) { SymmetricKey(data: $0) }
    }

    public func resetCredential(removingProtectedData: () throws -> Void) throws {
        try self.store.resetCredential(removingProtectedData: removingProtectedData)
    }
}
