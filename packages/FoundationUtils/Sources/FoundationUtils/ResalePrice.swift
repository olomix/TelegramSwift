import Foundation

/// The listing a resale purchase pays with: a TON-only gift can list a Stars
/// amount too, but only its TON amount can be charged.
public func resaleListing<Listing>(in listings: [Listing], tonOnly: Bool, isTon: (Listing) -> Bool) -> Listing? {
    return listings.first(where: { isTon($0) == tonOnly })
}

public enum ResaleChargeCap: Equatable {
    case amount(Int64)
    case currencyMismatch
}

/// The most a resale purchase may charge: the payment form's amount, or the
/// listed one if the form has no price. A form in another currency means the
/// listing is stale, and nanotons must never be compared with Stars.
public func resaleChargeCap(formCurrency: String, formAmount: Int64?, listedCurrency: String, listedAmount: Int64) -> ResaleChargeCap {
    guard formCurrency == listedCurrency else {
        return .currencyMismatch
    }
    return .amount(formAmount ?? listedAmount)
}

public enum ResaleFormDecision: Equatable {
    case send
    case priceRaised(Int64)
    case currencyMismatch
}

/// Whether the payment form may be paid after the user confirmed this price.
public func resaleFormDecision(formCurrency: String, formAmount: Int64?, confirmedCurrency: String, confirmedAmount: Int64) -> ResaleFormDecision {
    switch resaleChargeCap(formCurrency: formCurrency, formAmount: formAmount, listedCurrency: confirmedCurrency, listedAmount: confirmedAmount) {
    case .currencyMismatch:
        return .currencyMismatch
    case let .amount(amount):
        return amount > confirmedAmount ? .priceRaised(amount) : .send
    }
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
