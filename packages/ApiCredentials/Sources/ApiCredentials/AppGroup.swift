import Foundation

public enum AppGroup {
    /// True when `identifier` starts with a 10-character Apple team ID and a
    /// dot, the form macOS requires for an app group a sandboxed extension
    /// can share without a provisioning profile.
    public static func isTeamPrefixed(_ identifier: String) -> Bool {
        return identifier.range(of: "^[A-Z0-9]{10}\\.", options: .regularExpression) != nil
    }
}
