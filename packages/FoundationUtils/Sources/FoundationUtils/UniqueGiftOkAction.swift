/// Whether the viewer can manage a unique gift, as far as the app can tell.
public enum UniqueGiftOwnerAccess: Equatable {
    case manages
    case doesNotManage
    case unknown
}

public enum UniqueGiftOkAction: Equatable {
    case toggleProfileVisibility
    case buy
    case close
}

/// What the OK button of a unique gift screen does. Buying needs proof that the
/// viewer doesn't manage the gift, so an unknown owner only closes the screen.
public func uniqueGiftOkAction(managesSavedGift: Bool, isListed: Bool, ownerAccess: UniqueGiftOwnerAccess) -> UniqueGiftOkAction {
    if managesSavedGift {
        return .toggleProfileVisibility
    }
    if isListed && ownerAccess == .doesNotManage {
        return .buy
    }
    return .close
}
