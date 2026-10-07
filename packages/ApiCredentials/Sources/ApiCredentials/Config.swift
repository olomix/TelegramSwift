import Cocoa

public final class ApiEnvironment {
    /// Reads the credentials file on each access; nil when it is missing,
    /// unreadable or holds invalid values.
    public static var storedCredentials: ApiCredentialsValues? {
        guard let fileURL = credentialsFileURL else {
            return nil
        }
        return ApiCredentialsStore(fileURL: fileURL).load()
    }
    
    public static var bundleId: String {
        return "dev.alek.telegram"
    }
    public static var intentsBundleId: String {
        return teamId + "." + bundleId + ".FocusIntents"
    }
    public static var teamId: String {
        return "6N38VWS5BX"
    }
    
    
    
    /// `<TeamID>.dev.alek.telegram`, shared by the app and the Share
    /// extension and separate from the official client's group.
    public static var appGroup: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TGAppGroup") as? String, AppGroup.isTeamPrefixed(value) else {
            fatalError("TGAppGroup has no team prefix: set DEVELOPMENT_TEAM in Telegram-Mac/Secrets.xcconfig and sign with that team")
        }
        return value
    }

    /// The app group container; nil when the system cannot resolve the
    /// group, e.g. the build lacks the group entitlement.
    public static var dataRootURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// Where data lived before it moved into the app group container. Inside
    /// the App Sandbox this resolves into the app's own container instead.
    public static var legacyDataRootURL: URL? {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(bundleId)
    }

    /// At the group root, so every build type shares one file.
    public static var credentialsFileURL: URL? {
        return dataRootURL?.appendingPathComponent("api-credentials.json")
    }

    public static var containerURL: URL? {
        let containerUrl = dataRootURL?.appendingPathComponent(prefix)
        if let containerUrl = containerUrl {
            try? FileManager.default.createDirectory(at: containerUrl, withIntermediateDirectories: true, attributes: nil)
            return containerUrl
        }
        return nil
    }
    
    
    public static var appData: Data {
        let apiData = evaluateApiData() ?? ""
        let dict:[String: String] = ["bundleId": bundleId, "data": apiData]
        return try! JSONSerialization.data(withJSONObject: dict, options: [])
    }
    public static var language: String {
        return "macos"
    }
    
    public static var prefixList:[String] {
        return ["debug", "stable", "appstore", "beta"]
    }
    
    public static var resolvedDeviceName:[String : String]? {
        if let file = Bundle.main.path(forResource: "mac_devices", ofType: "txt") {
            if let string = try? String(contentsOf: .init(fileURLWithPath: file)) {
                let lines = string.components(separatedBy: "\n\n")
                
                var result:[String : String] = [:]
                for line in lines {
                    let resolved = line.components(separatedBy: "\n")
                    if resolved.count == 2 {
                        result[resolved[1]] = resolved[0]
                    }
                }
                
                return result
            }
        }
        return nil
    }
    
    public static var prefix: String {
        var prefix: String = ""
        switch Configuration.value(for: .source) {
        case "DEBUG":
            prefix = "debug"
        case "STABLE":
            prefix = "stable"
        case "APP_STORE":
            prefix = "appstore"
        default:
            prefix = "beta"
        }
        return prefix
    }
    
    public static var version: String {
        var suffix: String = ""
        
        suffix = Configuration.value(for: .source) ?? "DEBUG"
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? ""
        return "\(shortVersion) \(suffix)"
    }
    
    public static var premiumProductId: String {
        return "org.telegram.telegramPremium.monthly"
    }
}



