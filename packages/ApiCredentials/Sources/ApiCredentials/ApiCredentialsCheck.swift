import Foundation

/// What Telegram's servers said about a pair of credentials.
public enum ApiCredentialsCheckResult: Equatable {
    case accepted
    case rejected
    /// No answer in time: offline, or a network that needs a proxy.
    case unreachable
}

/// Raw outcome of the server request, before it is interpreted.
public enum ApiCredentialsCheckOutcome: Equatable {
    case token
    case serverError
    case timedOut

    /// Offline and FLOOD_WAIT are retried silently by the network layer,
    /// so they surface only as a timeout.
    public static let checkTimeout: TimeInterval = 15

    public var result: ApiCredentialsCheckResult {
        switch self {
        case .token:
            return .accepted
        case .serverError:
            return .rejected
        case .timedOut:
            return .unreachable
        }
    }
}

/// Decides when the app must ask for credentials.
public enum ApiCredentialsGate {
    public enum LaunchDecision: Equatable {
        case requireBeforeLaunch
        case launchAndCheckInBackground
    }

    public enum BackgroundCheckDecision: Equatable {
        case requireBlocking
        case none
    }

    public static func launchDecision(stored: ApiCredentialsValues?) -> LaunchDecision {
        return stored == nil ? .requireBeforeLaunch : .launchAndCheckInBackground
    }

    /// Only an explicit rejection blocks the user; being offline never does.
    public static func decision(afterBackgroundCheck result: ApiCredentialsCheckResult) -> BackgroundCheckDecision {
        switch result {
        case .rejected:
            return .requireBlocking
        case .accepted, .unreachable:
            return .none
        }
    }
}
