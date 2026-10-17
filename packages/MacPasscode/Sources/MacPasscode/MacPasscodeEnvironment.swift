import Foundation
import PasscodeCore

/// Keychain groups and scope for PasscodeCore in Telex.
public struct MacPasscodeEnvironment: Equatable {
    public static let biometricKeychainService = "telex.biometric"

    /// Shared by the app and the Share extension.
    public let sharedAccessGroup: String
    /// App only. Not the app group ID: on macOS the app group entitlement
    /// lets the extension read that keychain group as well.
    public let privateAccessGroup: String
    /// Per build type, so Debug and Release keep separate passcodes.
    public let keychainScope: String

    /// `teamPrefix` is `$(AppIdentifierPrefix)` (team ID and a dot) from
    /// Info.plist; nil when it is missing or was not expanded.
    public init?(teamPrefix: String?, buildPrefix: String) {
        guard let teamPrefix, teamPrefix.range(of: "^[A-Z0-9]{10}\\.$", options: .regularExpression) != nil,
              !buildPrefix.isEmpty else {
            return nil
        }
        self.sharedAccessGroup = teamPrefix + "com.korthane.telex.shared"
        self.privateAccessGroup = teamPrefix + "com.korthane.telex.private"
        self.keychainScope = "com.korthane.telex." + buildPrefix
    }

    public func configuration(for role: PasscodeConfiguration.ProcessRole) -> PasscodeConfiguration {
        // PasscodeCore uses `appGroupIdentifier` verbatim as the shared
        // keychain group on macOS.
        PasscodeConfiguration(appGroupIdentifier: self.sharedAccessGroup,
                              processRole: role,
                              biometricKeychainService: role == .mainApp ? Self.biometricKeychainService : nil,
                              keychainScope: self.keychainScope)
    }

    /// Configures PasscodeCore for `role` with the team prefix from
    /// `bundle`'s Info.plist key `TGKeychainGroupPrefix`, then marks the
    /// process available for key use. False when the prefix is missing or
    /// PasscodeCore refuses the configuration.
    public static func configureFromBundle(_ role: PasscodeConfiguration.ProcessRole, buildPrefix: String, bundle: Bundle = .main) -> Bool {
        let teamPrefix = bundle.object(forInfoDictionaryKey: "TGKeychainGroupPrefix") as? String
        guard let environment = MacPasscodeEnvironment(teamPrefix: teamPrefix, buildPrefix: buildPrefix),
              (try? environment.configure(role)) != nil else {
            return false
        }
        PasscodeSession.setApplicationAvailable(true)
        return true
    }

    /// For `.appExtension` also makes `store` refuse to create a credential
    /// when none exists, so the extension can never start a new one.
    public func configure(_ role: PasscodeConfiguration.ProcessRole,
                          environment: PasscodeEnvironment = .shared,
                          store: PasscodeCredentialStore = .shared) throws {
        let privateAccessGroup = self.privateAccessGroup
        try environment.configure(self.configuration(for: role),
                                  privateAccessGroup: role == .mainApp ? { privateAccessGroup } : nil)
        if role == .appExtension {
            store.requireExistingCredential()
        }
    }
}
