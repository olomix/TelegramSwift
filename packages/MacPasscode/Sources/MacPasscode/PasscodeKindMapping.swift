import PasscodeCore

public enum PasscodeKindMapping {
    /// The kind for a code set by the old Mac lock, which stored no kind:
    /// 4 or 6 digits (any script, as `PasscodeKind.normalize` folds them)
    /// map to `.digits4` / `.digits6`, everything else to `.alphanumeric`.
    public static func kind(for code: String) -> PasscodeKind {
        let normalized = PasscodeKind.digits4.normalize(code)
        guard normalized.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return .alphanumeric
        }
        switch normalized.count {
        case 4: return .digits4
        case 6: return .digits6
        default: return .alphanumeric
        }
    }
}
