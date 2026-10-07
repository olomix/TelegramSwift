import Foundation

/// What Telegram's servers said about a pair of credentials.
public enum ApiCredentialsCheckResult: Equatable {
    case accepted
    case rejected
    /// No usable answer: offline, a network that needs a proxy, or a server
    /// error that says nothing about the values.
    case unreachable

    /// Maps the error text of a failed `auth.exportLoginToken` request. Only
    /// errors that name the api_id reject the values.
    public init(serverError description: String) {
        switch description {
        case "API_ID_INVALID", "API_ID_PUBLISHED_FLOOD":
            self = .rejected
        default:
            self = .unreachable
        }
    }
}
