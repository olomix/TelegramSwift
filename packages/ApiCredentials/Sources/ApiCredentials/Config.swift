import Cocoa

public final class ApiEnvironment {
    // Credentials come from Telegram-Mac/Secrets.xcconfig via Info.plist.
    public static var apiId:Int32 {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TGApiId") as? String, let id = Int32(value), id != 0 else {
            fatalError("Missing TG_API_ID: copy Telegram-Mac/Secrets.example.xcconfig to Secrets.xcconfig and set your my.telegram.org credentials")
        }
        return id
    }
    public static var apiHash:String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TGApiHash") as? String, value.count == 32, value != String(repeating: "0", count: 32) else {
            fatalError("Missing TG_API_HASH: copy Telegram-Mac/Secrets.example.xcconfig to Secrets.xcconfig and set your my.telegram.org credentials")
        }
        return value
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
    
    
    
    // Keep data outside Telegram's app group so this build never shares
    // state with the official client.
    public static var dataRootURL: URL? {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(bundleId)
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



