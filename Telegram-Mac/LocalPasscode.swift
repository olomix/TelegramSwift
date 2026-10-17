//
//  LocalPasscode.swift
//  Telegram
//

import Cocoa
import LocalAuthentication
import SwiftSignalKit
import TelegramCore
import TGUIKit
import ApiCredentials
import InAppSettings
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
/// Settings and Touch ID live in `LocalPasscodeSettings`.
final class LocalPasscode {
    /// Key derivation is slow on purpose; keep it off the main thread.
    static let queue = Queue(name: "com.korthane.telex.passcode")

    enum LaunchStep {
        case unlocked(DatabaseKey)
        /// `offersForgetPasscode`: see `LaunchUnlock.canForgetPasscode()`.
        case needsPasscode(offersTouchId: Bool, offersForgetPasscode: Bool)
        case failed(Error)
    }

    let rootPath: String

    init(rootPath: String) {
        self.rootPath = rootPath
    }

    /// Configures PasscodeCore for the main app. False when the build lacks
    /// a valid keychain group prefix.
    static func configureEnvironment() -> Bool {
        return MacPasscodeEnvironment.configureFromBundle(.mainApp, buildPrefix: ApiEnvironment.prefix)
    }

    func openAccountManager() -> AccountManager<TelegramAccountManagerTypes> {
        let basePath = self.rootPath + "/accounts-metadata"
        // `setupAccountManager` minus the core's migration of legacy markers:
        // LaunchUnlock migrates the passcode together with the key file.
        return AccountManager<TelegramAccountManagerTypes>(basePath: basePath, isTemporary: false, isReadOnly: false, useCaches: true, removeDatabaseOnError: true, accessChallenge: AccountManagerAccessChallenge(
            prepare: { isFreshInstallation in
                let _ = try PasscodeEnvironment.shared.sharedAccessGroup()
                PasscodeCredentialStore.shared.configureLock(directory: basePath)
                if isFreshInstallation {
                    try self.resetLocalSecrets()
                }
            },
            resolve: { current, _ in
                return try self.resolveAccessChallenge(current)
            },
            finishInitialization: {
                try PasscodeCredentialStore.shared.resumeCleanup()
            }
        ))
    }

    private func resolveAccessChallenge(_ current: PostboxAccessChallengeData?) throws -> PostboxAccessChallengeData? {
        switch current {
        case .numericalPassword?, .plaintextPassword?:
            // A stale credential must not replace it; migration stores the
            // new state through `storeAccessChallenge`.
            if try self.launchUnlock(nil).keepsLegacyMarker() {
                return nil
            }
        default:
            break
        }
        let credentials = PasscodeCredentialStore.shared
        if case .secured? = current {
            credentials.requireExistingCredential()
        }
        guard let reference = try credentials.managedReference() else {
            return nil
        }
        return reference.map { accessChallengeData(reference: $0) } ?? PostboxAccessChallengeData.none
    }

    // MARK: Launch

    /// Decides how to open local data and opens it when no passcode is
    /// needed. Calls `completion` on the main queue.
    func prepareLaunch(accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping (LaunchStep) -> Void) {
        LocalPasscode.perform({
            // The account manager's `prepare` may still be resetting a fresh
            // installation on its own queue; wait for it.
            LocalPasscode.synchronousTransaction(accountManager) { _ in }
            do {
                return try self.launchStep(accountManager)
            } catch {
                return .failed(error)
            }
        }, completion: completion)
    }

    private func launchStep(_ accountManager: AccountManager<TelegramAccountManagerTypes>) throws -> LaunchStep {
        let unlock = self.launchUnlock(accountManager)
        switch try unlock.state() {
        case .fresh:
            return .unlocked(try unlock.createFresh())
        case .v2(needsPasscode: false):
            return .unlocked(try unlock.unlockV2(code: nil))
        case .legacy(needsPasscode: false):
            let markerCode = LocalPasscode.legacyMarkerCode(accountManager)
            return .unlocked(try unlock.unlockLegacy(code: nil, settingPasscode: markerCode))
        case .v2(needsPasscode: true):
            let biometricsEnabled = (try? unlock.isBiometricsEnabled()) ?? false
            return .needsPasscode(offersTouchId: TouchIdPolicy.offersUnlock(passcodeEnabled: true, biometricsEnabled: biometricsEnabled, deviceSupportsBiometrics: LocalPasscodeSettings.deviceSupportsBiometrics), offersForgetPasscode: false)
        case .legacy(needsPasscode: true):
            // The old key file needs the code itself to migrate.
            return .needsPasscode(offersTouchId: false, offersForgetPasscode: try unlock.canForgetPasscode())
        case .credentialLost:
            return .failed(LocalPasscodeError.credentialLost)
        }
    }

    /// Opens local data with the code typed at the launch lock, migrating
    /// the old key file if it is still in use.
    func unlock(code: String, accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping (Result<DatabaseKey, Error>) -> Void) {
        LocalPasscode.perform({
            Result {
                let unlock = self.launchUnlock(accountManager)
                switch try unlock.state() {
                case .v2:
                    return try unlock.unlockV2(code: code)
                case .legacy:
                    return try unlock.unlockLegacy(code: code)
                case .fresh, .credentialLost:
                    throw LocalPasscodeError.credentialLost
                }
            }
        }, completion: completion)
    }

    /// Opens local data with Touch ID at the launch lock. Disposing cancels
    /// the prompt.
    func unlockWithTouchId() -> Signal<DatabaseKey, Error> {
        let context = LocalPasscodeSettings.biometricContext(reason: strings().passcodeUnlockTouchIdReason)
        return Signal { subscriber in
            LocalPasscodeSettings.biometricQueue.async {
                do {
                    subscriber.putNext(try self.launchUnlock(nil).unlockV2(biometrics: context))
                    subscriber.putCompletion()
                } catch {
                    Logger.shared.log("LocalPasscode", "Touch ID launch unlock failed: \(error)")
                    subscriber.putError(error)
                }
            }
            return ActionDisposable {
                context.invalidate()
            }
        }
    }

    /// Drops a passcode that guards no encrypted key and opens local data
    /// without one; the user can set a new passcode in Settings.
    func forgetPasscode(accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping (Result<DatabaseKey, Error>) -> Void) {
        LocalPasscode.perform({
            Result { try self.launchUnlock(accountManager).forgetPasscode() }
        }, completion: completion)
    }

    /// Removes every account from this Mac without contacting the server,
    /// deletes local data and starts with a new database key. No account
    /// database may be open.
    func logOutAndReset(accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping (Result<DatabaseKey, Error>) -> Void) {
        LocalPasscode.perform({
            Result {
                try self.resetLocalSecrets()
                // Only now: a failed reset must leave the accounts signed in,
                // as the alert's Quit promises.
                LocalPasscode.synchronousTransaction(accountManager) { transaction in
                    for record in transaction.getRecords() {
                        transaction.updateRecord(record.id, { _ in nil })
                    }
                    transaction.removeAuth()
                }
                return try self.launchUnlock(accountManager).createFresh()
            }
        }, completion: completion)
    }

    /// Drops the passcode and the credential after a logout while the app
    /// keeps running with `databaseKey`, which is sealed again so the next
    /// launch can still open the databases. Completes only once that worked;
    /// otherwise the user retries or quits.
    func resetKeepingDatabaseKey(_ databaseKey: DatabaseKey, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Never, NoError> {
        return Signal { subscriber in
            self.resetKeepingDatabaseKey(databaseKey, accountManager: accountManager, completion: {
                subscriber.putCompletion()
            })
            return EmptyDisposable
        }
    }

    private func resetKeepingDatabaseKey(_ databaseKey: DatabaseKey, accountManager: AccountManager<TelegramAccountManagerTypes>, completion: @escaping () -> Void) {
        LocalPasscode.queue.async {
            do {
                try self.launchUnlock(accountManager).resetCredential(keeping: databaseKey)
                completion()
            } catch {
                Logger.shared.log("LocalPasscode", "reset after logout failed: \(error)")
                Queue.mainQueue().async {
                    // Going on would write new data under a key no file holds.
                    let alert = NSAlert()
                    alert.alertStyle = .critical
                    alert.messageText = "Cannot save the local data key"
                    alert.informativeText = LocalPasscode.describe(error) + "\n\nTry again, or quit; the next launch then offers what to do."
                    alert.addButton(withTitle: "Try Again")
                    alert.addButton(withTitle: "Quit")
                    if alert.runModal() == .alertFirstButtonReturn {
                        self.resetKeepingDatabaseKey(databaseKey, accountManager: accountManager, completion: completion)
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func resetLocalSecrets() throws {
        try self.launchUnlock(nil).resetLocalSecrets(removingData: {
            let fileManager = FileManager.default
            for name in try fileManager.contentsOfDirectory(atPath: self.rootPath) where name.hasPrefix("account-") {
                try fileManager.removeItem(atPath: self.rootPath + "/" + name)
            }
        })
    }

    private func launchUnlock(_ accountManager: AccountManager<TelegramAccountManagerTypes>?) -> LaunchUnlock {
        let directory = URL(fileURLWithPath: self.rootPath)
        return LaunchUnlock(databaseKeyFile: DatabaseKeyFile(directory: directory),
                            legacyKeyFile: LegacyKeyFile(directory: directory),
                            store: CoreLaunchCredentialStore(),
                            storeAccessChallenge: { reference in
                                if let accountManager {
                                    try LocalPasscode.storeAccessChallenge(reference, in: accountManager)
                                }
                            })
    }

    static func storeAccessChallenge(_ reference: PasscodeCredentialReference?, in accountManager: AccountManager<TelegramAccountManagerTypes>) throws {
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

    private static func perform<T>(_ body: @escaping () -> T, completion: @escaping (T) -> Void) {
        self.queue.async {
            let result = body()
            Queue.mainQueue().async {
                completion(result)
            }
        }
    }

    /// Must not run on the account manager's queue.
    static func synchronousTransaction<T>(_ accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (AccountManagerModifier<TelegramAccountManagerTypes>) -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        let _ = accountManager.transaction(f).startStandalone(next: { value in
            result = value
            semaphore.signal()
        })
        semaphore.wait()
        return result!
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case LocalPasscodeError.credentialLost:
            return PasscodeTexts.credentialLost
        case let PasscodeError.keychain(status):
            return PasscodeTexts.keychainError(status)
        case PasscodeError.corrupted:
            return PasscodeTexts.credentialCorrupted
        default:
            return "\(error)"
        }
    }
}
