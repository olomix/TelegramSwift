//
//  LocalPasscode.swift
//  Telegram
//

import Cocoa
import SwiftSignalKit
import TelegramCore
import TGUIKit
import ApiCredentials
import PasscodeCore
import PasscodeAccountManager
import MacPasscode

enum LocalPasscodeError: Error {
    /// Key files exist but the keychain item that opens them is gone.
    case credentialLost
    /// The account manager did not record the new passcode state.
    case accessChallengeNotStored
}

/// PasscodeCore wiring for the main app: keychain setup, the account
/// manager's access challenge, opening local data at launch, and resets.
final class LocalPasscode {
    /// Key derivation is slow on purpose; keep it off the main thread.
    static let queue = Queue(name: "com.korthane.telex.passcode")

    enum LaunchStep {
        case unlocked(DatabaseKey)
        case needsPasscode
        case failed(Error)
    }

    let rootPath: String

    init(rootPath: String) {
        self.rootPath = rootPath
    }

    /// Configures PasscodeCore for the main app. False when the build lacks
    /// a valid keychain group prefix.
    static func configureEnvironment() -> Bool {
        let teamPrefix = Bundle.main.object(forInfoDictionaryKey: "TGKeychainGroupPrefix") as? String
        guard let environment = MacPasscodeEnvironment(teamPrefix: teamPrefix, buildPrefix: ApiEnvironment.prefix) else {
            return false
        }
        do {
            try environment.configure(.mainApp)
        } catch {
            return false
        }
        PasscodeSession.setApplicationAvailable(true)
        return true
    }

    func openAccountManager() -> AccountManager<TelegramAccountManagerTypes> {
        let basePath = self.rootPath + "/accounts-metadata"
        // `setupAccountManager` minus the core's migration of legacy markers:
        // LaunchUnlock migrates the passcode together with the key file.
        return AccountManager<TelegramAccountManagerTypes>(basePath: basePath, isTemporary: false, isReadOnly: false, useCaches: true, removeDatabaseOnError: true, accessChallenge: AccountManagerAccessChallenge(
            prepare: { [rootPath = self.rootPath] isFreshInstallation in
                let _ = try PasscodeEnvironment.shared.sharedAccessGroup()
                PasscodeCredentialStore.shared.configureLock(directory: basePath)
                if isFreshInstallation {
                    try LocalPasscode(rootPath: rootPath).resetLocalSecrets(removingAccountDatabases: true)
                }
            },
            resolve: { current, _ in
                return try LocalPasscode.resolveAccessChallenge(current)
            },
            finishInitialization: {
                try PasscodeCredentialStore.shared.resumeCleanup()
            }
        ))
    }

    private static func resolveAccessChallenge(_ current: PostboxAccessChallengeData?) throws -> PostboxAccessChallengeData? {
        let credentials = PasscodeCredentialStore.shared
        if case .secured? = current {
            credentials.requireExistingCredential()
        }
        guard let reference = try credentials.managedReference() else {
            return nil
        }
        return reference.map { accessChallengeData(reference: $0) } ?? PostboxAccessChallengeData.none
    }

    /// Whether the passcode protects local data, for settings rows.
    static func hasPasscode(_ data: PostboxAccessChallengeData) -> Bool {
        if case .none = data {
            return false
        }
        return (try? PasscodeCredentialStore.shared.protectionSettings().enabled) ?? true
    }

    // MARK: Launch

    /// Decides how to open local data and opens it when no passcode is
    /// needed. Calls `completion` on the main queue.
    func prepareLaunch(accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping (LaunchStep) -> Void) {
        LocalPasscode.queue.async {
            // The account manager's `prepare` may still be resetting a fresh
            // installation on its own queue; wait for it.
            LocalPasscode.synchronousTransaction(accountManager) { _ in }
            let step: LaunchStep
            do {
                let unlock = self.launchUnlock(accountManager)
                switch try unlock.state() {
                case .fresh:
                    step = .unlocked(try unlock.createFresh())
                case .v2(needsPasscode: false):
                    step = .unlocked(try unlock.unlockV2(code: nil))
                case .legacy(needsPasscode: false):
                    let markerCode = LocalPasscode.legacyMarkerCode(accountManager)
                    step = .unlocked(try unlock.unlockLegacy(code: nil, settingPasscode: markerCode))
                case .v2(needsPasscode: true), .legacy(needsPasscode: true):
                    step = .needsPasscode
                case .credentialLost:
                    step = .failed(LocalPasscodeError.credentialLost)
                }
            } catch {
                step = .failed(error)
            }
            Queue.mainQueue().async {
                completion(step)
            }
        }
    }

    /// Opens local data with the code typed at the launch lock, migrating
    /// the old key file if it is still in use.
    func unlock(code: String, accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping (Result<DatabaseKey, Error>) -> Void) {
        LocalPasscode.queue.async {
            let result = Result<DatabaseKey, Error>(catching: {
                let unlock = self.launchUnlock(accountManager)
                switch try unlock.state() {
                case .v2:
                    return try unlock.unlockV2(code: code)
                case .legacy:
                    return try unlock.unlockLegacy(code: code)
                case .fresh, .credentialLost:
                    throw LocalPasscodeError.credentialLost
                }
            })
            Queue.mainQueue().async {
                completion(result)
            }
        }
    }

    /// Removes every account from this Mac without contacting the server,
    /// deletes local data and starts with a new database key. No account
    /// database may be open.
    func logOutAndReset(accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping (Result<DatabaseKey, Error>) -> Void) {
        LocalPasscode.queue.async {
            let result = Result<DatabaseKey, Error>(catching: {
                LocalPasscode.synchronousTransaction(accountManager) { transaction in
                    for record in transaction.getRecords() {
                        transaction.updateRecord(record.id, { _ in nil })
                    }
                    transaction.removeAuth()
                }
                try self.resetLocalSecrets(removingAccountDatabases: true)
                return try self.launchUnlock(accountManager).createFresh()
            })
            Queue.mainQueue().async {
                completion(result)
            }
        }
    }

    /// Drops the passcode and the credential after a logout while the app
    /// keeps running with `databaseKey`, which is sealed again so the next
    /// launch can still open the databases.
    func resetKeepingDatabaseKey(_ databaseKey: DatabaseKey, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Never, NoError> {
        return Signal { subscriber in
            LocalPasscode.queue.async {
                do {
                    try self.resetLocalSecrets(removingAccountDatabases: false)
                    try self.launchUnlock(accountManager).sealAfterReset(databaseKey)
                } catch {
                    Logger.shared.log("LocalPasscode", "reset after logout failed: \(error)")
                }
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }

    private func resetLocalSecrets(removingAccountDatabases: Bool) throws {
        try self.launchUnlock(nil).resetLocalSecrets(removingData: {
            guard removingAccountDatabases else {
                return
            }
            let fileManager = FileManager.default
            for name in try fileManager.contentsOfDirectory(atPath: self.rootPath) where name.hasPrefix("account-") {
                try fileManager.removeItem(atPath: self.rootPath + "/" + name)
            }
        })
    }

    private func launchUnlock(_ accountManager: AccountManager<TelegramAccountManagerTypes>?) -> LaunchUnlock {
        let directory = URL(fileURLWithPath: self.rootPath)
        return LaunchUnlock(databaseKeyFile: DatabaseKeyFile(directory: directory),
                            legacyKeyReader: LegacyKeyReader(directory: directory),
                            store: CoreLaunchCredentialStore(),
                            storeAccessChallenge: { reference in
                                if let accountManager {
                                    try LocalPasscode.storeAccessChallenge(reference, in: accountManager)
                                }
                            })
    }

    private static func storeAccessChallenge(_ reference: PasscodeCredentialReference?, in accountManager: AccountManager<TelegramAccountManagerTypes>) throws {
        let data = reference.map { accessChallengeData(reference: $0) } ?? PostboxAccessChallengeData.none
        let stored = synchronousTransaction(accountManager) { transaction -> Bool in
            transaction.setAccessChallengeData(data)
            return transaction.getAccessChallengeData() == data
        }
        // `.none` is kept back while the credential was never migrated or
        // reset; the old marker then stays, as the old code would have.
        if reference != nil, !stored {
            throw LocalPasscodeError.accessChallengeNotStored
        }
    }

    /// The code an old build kept in the account manager itself; the Mac's
    /// own marker is empty.
    private static func legacyMarkerCode(_ accountManager: AccountManager<TelegramAccountManagerTypes>) -> String? {
        let data = synchronousTransaction(accountManager) { $0.getAccessChallengeData() }
        switch data {
        case let .numericalPassword(value), let .plaintextPassword(value):
            return value.isEmpty ? nil : value
        default:
            return nil
        }
    }

    /// Must not run on the account manager's queue.
    private static func synchronousTransaction<T>(_ accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (AccountManagerModifier<TelegramAccountManagerTypes>) -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        let _ = accountManager.transaction(f).startStandalone(next: { value in
            result = value
            semaphore.signal()
        })
        semaphore.wait()
        return result!
    }

    // MARK: Settings and runtime lock

    /// Unlocks the running app.
    static func verifyAppUnlock(_ code: String) -> Signal<Void, PasscodeCheckFailure> {
        return self.run {
            try PasscodeCredentialStore.shared.verify(code, scope: .appUnlock).invalidate()
        }
    }

    /// Turns the passcode on. The credential must already exist: a new one
    /// would carry a new access key that no longer opens `db-key.v2`.
    static func setPasscode(_ code: String, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, PasscodeCheckFailure> {
        return self.run {
            let store = PasscodeCredentialStore.shared
            guard try store.hasStoredCredential() else {
                throw PasscodeError.unavailable
            }
            let reference = try store.setPasscode(code, kind: PasscodeKindMapping.kind(for: code), session: nil)
            try self.storeAccessChallenge(reference, in: accountManager)
        }
    }

    static func changePasscode(current: String, to code: String, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, PasscodeCheckFailure> {
        return self.run {
            let store = PasscodeCredentialStore.shared
            let session = try store.verify(current, scope: .managePasscode)
            defer { session.invalidate() }
            let reference = try store.setPasscode(code, kind: PasscodeKindMapping.kind(for: code), session: session)
            try self.storeAccessChallenge(reference, in: accountManager)
        }
    }

    static func disablePasscode(current: String, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, PasscodeCheckFailure> {
        return self.run {
            let store = PasscodeCredentialStore.shared
            let session = try store.verify(current, scope: .managePasscode)
            defer { session.invalidate() }
            try store.disablePasscode(session: session)
            try self.storeAccessChallenge(nil, in: accountManager)
        }
    }

    private static func run(_ body: @escaping () throws -> Void) -> Signal<Void, PasscodeCheckFailure> {
        return Signal { subscriber in
            LocalPasscode.queue.async {
                do {
                    try body()
                    subscriber.putNext(Void())
                    subscriber.putCompletion()
                } catch {
                    Logger.shared.log("LocalPasscode", "passcode operation failed: \(error)")
                    subscriber.putError(PasscodeCheckFailure(error))
                }
            }
            return EmptyDisposable
        }
    }

    // MARK: Texts

    // New strings are English only, like the other Telex-specific alerts.
    static func cooldownText(_ seconds: Int) -> String {
        return "Too many attempts. Try again in \(seconds) s."
    }

    static let unavailableText = "The passcode cannot be checked: its keychain item is missing or unreadable."

    static func failureText(_ failure: PasscodeCheckFailure) -> String {
        switch failure {
        case .invalidCode:
            return strings().passcodeControllerErrorCurrent
        case let .cooldown(seconds):
            return self.cooldownText(seconds)
        case .unavailable:
            return self.unavailableText
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case LocalPasscodeError.credentialLost:
            return "The keychain item that opens local data on this Mac is missing."
        case let PasscodeError.keychain(status):
            return "The keychain returned error \(status)."
        case PasscodeError.corrupted:
            return "The passcode keychain item is damaged."
        default:
            return "\(error)"
        }
    }
}

extension PasscodeLockView {
    /// Feedback for a failed check on a lock screen.
    func show(_ failure: PasscodeCheckFailure) {
        self.input.shake()
        switch failure {
        case .invalidCode:
            break
        case .cooldown, .unavailable:
            if let window = self.window as? Window {
                showModalText(for: window, text: LocalPasscode.failureText(failure))
            }
        }
    }
}
