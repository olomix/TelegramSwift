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
        XCTAssertEqual(resaleChargeCap(formCurrency: "XTR", formAmount: 120, listedCurrency: "XTR", listedAmount: 100), .amount(120))
    }

    func testTonFormForStarsListingHasNoCap() {
        XCTAssertEqual(resaleChargeCap(formCurrency: "TON", formAmount: 5_000_000_000, listedCurrency: "XTR", listedAmount: 100), .currencyMismatch)
    }

    func testStarsFormForTonListingHasNoCap() {
        XCTAssertEqual(resaleChargeCap(formCurrency: "XTR", formAmount: 100, listedCurrency: "TON", listedAmount: 5_000_000_000), .currencyMismatch)
    }

    func testFormWithoutPricesKeepsTheListedAmount() {
        XCTAssertEqual(resaleChargeCap(formCurrency: "XTR", formAmount: nil, listedCurrency: "XTR", listedAmount: 100), .amount(100))
    }

    func testStarsFormBelowANanotonCapIsNotSent() {
        XCTAssertEqual(resaleFormDecision(formCurrency: "XTR", formAmount: 100, confirmedCurrency: "TON", confirmedAmount: 5_000_000_000), .currencyMismatch)
    }

    func testTonFormAboveAStarsCapIsNotAPriceRise() {
        XCTAssertEqual(resaleFormDecision(formCurrency: "TON", formAmount: 5_000_000_000, confirmedCurrency: "XTR", confirmedAmount: 100), .currencyMismatch)
    }

    func testMismatchedFormWithoutPricesIsNotSent() {
        XCTAssertEqual(resaleFormDecision(formCurrency: "XTR", formAmount: nil, confirmedCurrency: "TON", confirmedAmount: 7), .currencyMismatch)
    }

    func testFormAtOrBelowTheConfirmedPriceIsSent() {
        XCTAssertEqual(resaleFormDecision(formCurrency: "TON", formAmount: 7, confirmedCurrency: "TON", confirmedAmount: 7), .send)
        XCTAssertEqual(resaleFormDecision(formCurrency: "XTR", formAmount: 90, confirmedCurrency: "XTR", confirmedAmount: 100), .send)
    }

    func testFormWithoutPricesInTheConfirmedCurrencyIsSent() {
        XCTAssertEqual(resaleFormDecision(formCurrency: "XTR", formAmount: nil, confirmedCurrency: "XTR", confirmedAmount: 100), .send)
    }

    func testFormAboveTheConfirmedPriceIsAPriceRise() {
        XCTAssertEqual(resaleFormDecision(formCurrency: "XTR", formAmount: 120, confirmedCurrency: "XTR", confirmedAmount: 100), .priceRaised(120))
    }

    func testTonAmountKeepsEveryDigit() {
        XCTAssertEqual(trimmingTrailingFractionZeros("1.239000000"), "1.239")
        XCTAssertEqual(trimmingTrailingFractionZeros("1.234567891"), "1.234567891")
    }

    func testTonAmountBelowOneCentIsNotZero() {
        XCTAssertEqual(trimmingTrailingFractionZeros("0.009000000"), "0.009")
        XCTAssertEqual(trimmingTrailingFractionZeros("0.000000001"), "0.000000001")
    }

    func testWholeTonAmountDropsTheFraction() {
        XCTAssertEqual(trimmingTrailingFractionZeros("5.000000000"), "5")
        XCTAssertEqual(trimmingTrailingFractionZeros("1,000.100000000"), "1,000.1")
    }

    func testZerosOfAnIntegerAreKept() {
        XCTAssertEqual(trimmingTrailingFractionZeros("100"), "100")
        XCTAssertEqual(trimmingTrailingFractionZeros("100.000000000"), "100")
    }
}
