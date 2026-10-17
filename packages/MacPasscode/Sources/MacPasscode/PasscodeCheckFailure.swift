import PasscodeCore

/// How a lock screen reacts to a failed passcode check.
public enum PasscodeCheckFailure: Equatable {
    /// Shake the field.
    case invalidCode
    /// Show the wait; the code was not checked.
    case cooldown(seconds: Int)
    /// The credential cannot be used at all.
    case unavailable

    public init(_ error: Error) {
        switch error {
        case PasscodeError.invalidCode, LaunchUnlockError.invalidCode:
            self = .invalidCode
        case let PasscodeError.cooldown(seconds):
            self = .cooldown(seconds: max(1, seconds))
        default:
            self = .unavailable
        }
    }
}
