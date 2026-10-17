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
public struct TouchIdCarryOver {
    public enum Outcome: Equatable {
        /// Nothing to do now; the old setting is kept for a later unlock.
        case skipped
        /// The old setting was dropped without enabling anything.
        case settingCleared
        case enabled
        /// Enabling failed or was cancelled; the passcode keeps working.
        case failed
    }

    private let readLegacySetting: () -> Bool
    private let clearLegacySetting: () -> Void
    private let protection: () throws -> (passcodeEnabled: Bool, biometricsEnabled: Bool)
    private let deviceSupportsBiometrics: () -> Bool
    private let enableBiometrics: (String) throws -> Void

    /// `enableBiometrics` verifies the code and enables Touch ID; it may
    /// show the Touch ID prompt.
    public init(readLegacySetting: @escaping () -> Bool,
                clearLegacySetting: @escaping () -> Void,
                protection: @escaping () throws -> (passcodeEnabled: Bool, biometricsEnabled: Bool),
                deviceSupportsBiometrics: @escaping () -> Bool,
                enableBiometrics: @escaping (String) throws -> Void) {
        self.readLegacySetting = readLegacySetting
        self.clearLegacySetting = clearLegacySetting
        self.protection = protection
        self.deviceSupportsBiometrics = deviceSupportsBiometrics
        self.enableBiometrics = enableBiometrics
    }

    /// Runs with the code that just unlocked. Never throws.
    @discardableResult
    public func run(code: String) -> Outcome {
        guard self.readLegacySetting(), let protection = try? self.protection() else {
            return .skipped
        }
        if protection.biometricsEnabled || !protection.passcodeEnabled {
            self.clearLegacySetting()
            return .settingCleared
        }
        // The sensor may only be away for now (lid closed); try next time.
        guard self.deviceSupportsBiometrics() else {
            return .skipped
        }
        // One attempt: a cancelled prompt counts as the user's answer.
        defer { self.clearLegacySetting() }
        do {
            try self.enableBiometrics(code)
            return .enabled
        } catch {
            return .failed
        }
    }
}
