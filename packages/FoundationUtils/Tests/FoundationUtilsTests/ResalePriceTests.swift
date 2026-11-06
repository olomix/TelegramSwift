import XCTest
@testable import FoundationUtils

final class ResalePriceTests: XCTestCase {
    private struct Listing: Equatable {
        let isTon: Bool
        let amount: Int64
    }

    private let stars = Listing(isTon: false, amount: 100)
    private let ton = Listing(isTon: true, amount: 5_000_000_000)

    private func listing(_ listings: [Listing], tonOnly: Bool) -> Listing? {
        return resaleListing(in: listings, tonOnly: tonOnly, isTon: { $0.isTon })
    }

    func testTonOnlyGiftWithBothListingsPaysInTon() {
        XCTAssertEqual(listing([stars, ton], tonOnly: true), ton)
    }

    func testOtherGiftWithBothListingsPaysInStars() {
        XCTAssertEqual(listing([ton, stars], tonOnly: false), stars)
    }

    func testMissingListingInRequiredCurrencyIsNil() {
        XCTAssertNil(listing([stars], tonOnly: true))
        XCTAssertNil(listing([ton], tonOnly: false))
        XCTAssertNil(listing([], tonOnly: false))
    }

    func testMatchingFormSetsTheCap() {
        XCTAssertEqual(resaleChargeCap(formCurrency: "XTR", formAmount: 120, listedCurrency: "XTR", listedAmount: 100), 120)
    }

    func testCurrencyMismatchKeepsTheListedAmount() {
        XCTAssertEqual(resaleChargeCap(formCurrency: "TON", formAmount: 5_000_000_000, listedCurrency: "XTR", listedAmount: 100), 100)
    }

    func testNoFormKeepsTheListedAmount() {
        XCTAssertEqual(resaleChargeCap(formCurrency: nil, formAmount: nil, listedCurrency: "TON", listedAmount: 7), 7)
    }

    func testFormWithoutPricesKeepsTheListedAmount() {
        XCTAssertEqual(resaleChargeCap(formCurrency: "XTR", formAmount: nil, listedCurrency: "XTR", listedAmount: 100), 100)
    }
}
