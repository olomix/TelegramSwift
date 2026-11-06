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

/// The most a resale may charge: the form's amount, or the listed one if it
/// has no price. A form in another currency means the listing is stale.
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
