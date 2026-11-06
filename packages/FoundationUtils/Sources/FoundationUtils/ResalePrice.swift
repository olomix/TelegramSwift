import Foundation

/// The listing a resale purchase pays with: a TON-only gift can list a Stars
/// amount too, but only its TON amount can be charged.
public func resaleListing<Listing>(in listings: [Listing], tonOnly: Bool, isTon: (Listing) -> Bool) -> Listing? {
    return listings.first(where: { isTon($0) == tonOnly })
}

/// The most a resale purchase may charge: the payment form's amount when it is
/// in the listing's currency, so nanotons are never read as Stars or the reverse.
public func resaleChargeCap(formCurrency: String?, formAmount: Int64?, listedCurrency: String, listedAmount: Int64) -> Int64 {
    if formCurrency == listedCurrency, let formAmount = formAmount {
        return formAmount
    }
    return listedAmount
}

/// Drops only the zeros that end a fraction, keeping every other digit:
/// "1.239000000" becomes "1.239" and "5.000000000" becomes "5".
public func trimmingTrailingFractionZeros(_ amount: String) -> String {
    guard amount.contains(".") else {
        return amount
    }
    var trimmed = Substring(amount)
    while trimmed.hasSuffix("0") {
        trimmed.removeLast()
    }
    if trimmed.hasSuffix(".") {
        trimmed.removeLast()
    }
    return String(trimmed)
}

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
