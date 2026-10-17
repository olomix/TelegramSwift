/// Telex-specific passcode texts for the app and the Share extension.
/// English only, like the other Telex-specific texts.
public enum PasscodeTexts {
    private static let keychainItemUnreadable = "its keychain item is missing or unreadable"

    public static func cooldown(seconds: Int) -> String {
        "Too many attempts. Try again in \(seconds) s."
    }

    public static let passcodeUnavailable = "The passcode cannot be checked: \(keychainItemUnreadable)."
    public static let touchIdEnableReason = "turn on unlocking with Touch ID"
    public static let touchIdNotEnabled = "Touch ID was not turned on. The passcode still works."

    public static let credentialLost = "The keychain item that opens local data on this Mac is missing."
    public static let credentialCorrupted = "The passcode keychain item is damaged."

    public static func keychainError(_ status: Int32) -> String {
        "The keychain returned error \(status)."
    }

    public static let shareFinishUpdate = "Open Telex once to finish the update, then share again."
    public static let shareUnavailable = "Telex cannot open local data from here: \(keychainItemUnreadable). Open Telex to fix this."
}
