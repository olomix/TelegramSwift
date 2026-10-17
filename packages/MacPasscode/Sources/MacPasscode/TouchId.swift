import PasscodeCore

/// Where Touch ID shows up: the settings row and the lock screens.
public enum TouchIdPolicy {
    /// The settings toggle needs a passcode. It stays while Touch ID is on
    /// but the sensor is away (lid closed), so it can still be turned off.
    public static func showsToggle(passcodeEnabled: Bool, biometricsEnabled: Bool, deviceSupportsBiometrics: Bool) -> Bool {
        passcodeEnabled && (deviceSupportsBiometrics || biometricsEnabled)
    }

    /// Lock screens try Touch ID first, then fall back to the code.
    public static func offersUnlock(passcodeEnabled: Bool, biometricsEnabled: Bool, deviceSupportsBiometrics: Bool) -> Bool {
        passcodeEnabled && biometricsEnabled && deviceSupportsBiometrics
    }
}

/// Moves the old UI-only `useTouchId` setting onto PasscodeCore. Enabling
/// needs a session verified with the code, so it runs after a passcode
/// unlock.
public enum TouchIdCarryOver {
    public enum Outcome: Equatable {
        /// Nothing to do now; the old setting is kept for a later unlock.
        case skipped
        /// The old setting was dropped without enabling anything.
        case settingCleared
        case enabled
        /// Enabling failed or was cancelled; the passcode keeps working.
        case failed
    }

    /// Runs with the `code` that just unlocked. Never throws.
    /// `enableBiometrics` verifies the code and enables Touch ID; it may show
    /// the Touch ID prompt.
    @discardableResult
    public static func run(code: String,
                           readLegacySetting: () -> Bool,
                           clearLegacySetting: () -> Void,
                           protection: () throws -> (passcodeEnabled: Bool, biometricsEnabled: Bool),
                           deviceSupportsBiometrics: () -> Bool,
                           enableBiometrics: (String) throws -> Void) -> Outcome {
        guard readLegacySetting(), let protection = try? protection() else {
            return .skipped
        }
        if protection.biometricsEnabled || !protection.passcodeEnabled {
            clearLegacySetting()
            return .settingCleared
        }
        // The sensor may only be away for now (lid closed); try next time.
        guard deviceSupportsBiometrics() else {
            return .skipped
        }
        // One attempt: a cancelled prompt counts as the user's answer.
        defer { clearLegacySetting() }
        do {
            try enableBiometrics(code)
            return .enabled
        } catch {
            return .failed
        }
    }
}
