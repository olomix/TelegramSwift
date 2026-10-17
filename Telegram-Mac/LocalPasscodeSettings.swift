//
//  LocalPasscodeSettings.swift
//  Telegram
//

import Cocoa
import LocalAuthentication
import SwiftSignalKit
import TelegramCore
import InAppSettings
import PasscodeCore
import MacPasscode

/// Passcode and Touch ID for the running app: settings changes and the
/// runtime lock.
enum LocalPasscodeSettings {
    /// Whether the passcode protects local data, for settings rows.
    static func hasPasscode(_ data: PostboxAccessChallengeData) -> Bool {
        if case .none = data {
            return false
        }
        return (try? PasscodeCredentialStore.shared.protectionSettings().enabled) ?? true
    }

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
            try LocalPasscode.storeAccessChallenge(reference, in: accountManager)
        }
    }

    static func changePasscode(current: String, to code: String, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, PasscodeCheckFailure> {
        return self.run {
            let store = PasscodeCredentialStore.shared
            let session = try store.verify(current, scope: .managePasscode)
            defer { session.invalidate() }
            let reference = try store.setPasscode(code, kind: PasscodeKindMapping.kind(for: code), session: session)
            try LocalPasscode.storeAccessChallenge(reference, in: accountManager)
        }
    }

    static func disablePasscode(current: String, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, PasscodeCheckFailure> {
        return self.run {
            let store = PasscodeCredentialStore.shared
            let session = try store.verify(current, scope: .managePasscode)
            defer { session.invalidate() }
            try store.disablePasscode(session: session)
            try LocalPasscode.storeAccessChallenge(nil, in: accountManager)
        }
    }

    private static func run<T>(on queue: Queue = LocalPasscode.queue, _ body: @escaping () throws -> T) -> Signal<T, PasscodeCheckFailure> {
        return Signal { subscriber in
            queue.async {
                do {
                    subscriber.putNext(try body())
                    subscriber.putCompletion()
                } catch {
                    Logger.shared.log("LocalPasscode", "passcode operation failed: \(error)")
                    subscriber.putError(PasscodeCheckFailure(error))
                }
            }
            return EmptyDisposable
        }
    }

    // MARK: Touch ID

    /// A Touch ID prompt blocks its thread until answered; keep it off
    /// `LocalPasscode.queue` so a typed code is still checked meanwhile.
    static let biometricQueue = Queue(name: "com.korthane.telex.passcode.biometric")

    static var deviceSupportsBiometrics: Bool {
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func biometricContext(reason: String) -> LAContext {
        let context = LAContext()
        context.localizedReason = reason
        return context
    }

    /// Whether lock screens try Touch ID before the code.
    static func offersTouchIdUnlock() -> Bool {
        guard let settings = try? PasscodeCredentialStore.shared.protectionSettings() else {
            return false
        }
        return TouchIdPolicy.offersUnlock(passcodeEnabled: settings.enabled, biometricsEnabled: settings.biometricsEnabled, deviceSupportsBiometrics: self.deviceSupportsBiometrics)
    }

    /// The settings toggle: nil hides it, otherwise whether Touch ID is on.
    static func touchIdToggleState() -> Signal<Bool?, NoError> {
        let changes = Signal<Void, NoError>.single(Void()) |> then(PasscodeCredentialStore.shared.changes)
        return changes |> deliverOn(Queue.concurrentDefaultQueue()) |> map { _ -> Bool? in
            guard let settings = try? PasscodeCredentialStore.shared.protectionSettings(),
                  TouchIdPolicy.showsToggle(passcodeEnabled: settings.enabled, biometricsEnabled: settings.biometricsEnabled, deviceSupportsBiometrics: self.deviceSupportsBiometrics) else {
                return nil
            }
            return settings.biometricsEnabled
        } |> distinctUntilChanged
    }

    /// Unlocks the running app with Touch ID: true on success, false when
    /// the prompt was cancelled or failed. Disposing cancels the prompt.
    static func touchIdAppUnlock() -> Signal<Bool, NoError> {
        let context = self.biometricContext(reason: strings().passcodeUnlockTouchIdReason)
        return Signal { subscriber in
            self.biometricQueue.async {
                do {
                    // PasscodeCore gives Touch ID sessions for resource scopes only.
                    try PasscodeCredentialStore.shared.authenticateBiometrics(context: context, scope: .resource(namespace: CoreLaunchCredentialStore.namespace)).invalidate()
                    subscriber.putNext(true)
                } catch {
                    Logger.shared.log("LocalPasscode", "Touch ID unlock failed: \(error)")
                    subscriber.putNext(false)
                }
                subscriber.putCompletion()
            }
            return ActionDisposable {
                context.invalidate()
            }
        }
    }

    /// Turns Touch ID on or off with the current code; false when it could
    /// not be turned on. Disposing cancels the Touch ID prompt.
    static func setTouchId(_ enabled: Bool, current: String, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, PasscodeCheckFailure> {
        let context = self.biometricContext(reason: PasscodeTexts.touchIdEnableReason)
        let toggle = self.run(on: self.biometricQueue) { () -> Bool in
            let store = PasscodeCredentialStore.shared
            let session = try store.verify(current, scope: .settings)
            defer { session.invalidate() }
            // An explicit choice replaces the pending carry-over.
            self.clearLegacyTouchIdSetting(accountManager)
            guard enabled else {
                try store.disableBiometrics(session: session)
                return true
            }
            do {
                try store.enableBiometrics(session: session, context: context)
                return true
            } catch {
                Logger.shared.log("LocalPasscode", "enabling Touch ID failed: \(error)")
                return false
            }
        }
        return Signal { subscriber in
            let disposable = toggle.start(next: subscriber.putNext, error: subscriber.putError, completed: subscriber.putCompletion)
            return ActionDisposable {
                context.invalidate()
                disposable.dispose()
            }
        }
    }

    /// Moves the old UI-only Touch ID setting onto PasscodeCore after a
    /// passcode unlock with `code`. Failures leave Touch ID off.
    static func carryOverTouchId(code: String, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        let context = self.biometricContext(reason: PasscodeTexts.touchIdEnableReason)
        self.biometricQueue.async {
            let store = PasscodeCredentialStore.shared
            let outcome = TouchIdCarryOver.run(code: code, readLegacySetting: {
                return LocalPasscode.synchronousTransaction(accountManager) { transaction in
                    transaction.getSharedData(ApplicationSharedPreferencesKeys.additionalSettings)?.get(AdditionalSettings.self)?.useTouchId ?? false
                }
            }, clearLegacySetting: {
                self.clearLegacyTouchIdSetting(accountManager)
            }, protection: {
                let settings = try store.protectionSettings()
                return (settings.enabled, settings.biometricsEnabled)
            }, deviceSupportsBiometrics: {
                return self.deviceSupportsBiometrics
            }, enableBiometrics: { code in
                let session = try store.verify(code, scope: .settings)
                defer { session.invalidate() }
                try store.enableBiometrics(session: session, context: context)
            })
            Logger.shared.log("LocalPasscode", "Touch ID carry-over: \(outcome)")
        }
    }

    private static func clearLegacyTouchIdSetting(_ accountManager: AccountManager<TelegramAccountManagerTypes>) {
        let _ = updateAdditionalSettingsInteractively(accountManager: accountManager, { $0.withUpdatedTouchId(false) }).startStandalone()
    }
}

/// Starts the Touch ID prompt of a lock screen at most once, and only
/// while the app is active.
struct TouchIdAutoPrompt {
    private var prompted = false

    mutating func promptIfNeeded(enabled: Bool, _ prompt: () -> Void) {
        guard NSApp.isActive, enabled, !prompted else {
            return
        }
        prompted = true
        prompt()
    }
}

extension PasscodeCheckFailure {
    var text: String {
        switch self {
        case .invalidCode:
            return strings().passcodeControllerErrorCurrent
        case let .cooldown(seconds):
            return PasscodeTexts.cooldown(seconds: seconds)
        case .unavailable:
            return PasscodeTexts.passcodeUnavailable
        }
    }
}
