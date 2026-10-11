import Foundation
import SwiftSignalKit
import TelegramCore

// The Mac keeps its passcode outside TelegramCore and stores only a marker in
// the account manager. The core now commits a marker only when the access
// challenge resolver returns it, so the resolver hands back the value being set.
private let pendingAccessChallengeData = Atomic<PostboxAccessChallengeData?>(value: nil)

extension AccountManagerAccessChallenge {
    /// Keeps whatever marker is stored and never migrates it. Pair it with
    /// `AccountManagerModifier.storeAccessChallengeData`; a plain
    /// `setAccessChallengeData` is dropped by the core.
    public static var passthrough: AccountManagerAccessChallenge {
        return AccountManagerAccessChallenge(
            prepare: { _ in },
            resolve: { current, _ in
                return current ?? pendingAccessChallengeData.with { $0 }
            },
            finishInitialization: {}
        )
    }
}

extension AccountManagerModifier {
    /// Stores the passcode marker. Requires an account manager created with
    /// `AccountManagerAccessChallenge.passthrough`.
    public func storeAccessChallengeData(_ data: PostboxAccessChallengeData) {
        let _ = pendingAccessChallengeData.swap(data)
        self.setAccessChallengeData(data)
        let _ = pendingAccessChallengeData.swap(nil)
        assert(self.getAccessChallengeData() == data, "the core did not commit the passcode marker")
    }
}
