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
