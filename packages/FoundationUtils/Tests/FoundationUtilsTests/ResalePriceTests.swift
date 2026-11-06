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

    func testManagerOfASavedGiftTogglesItEvenWhenListed() {
        XCTAssertEqual(uniqueGiftOkAction(managesSavedGift: true, isListed: true, ownerAccess: .manages), .toggleProfileVisibility)
    }

    func testOnlyAProvenNonManagerCanBuy() {
        XCTAssertEqual(uniqueGiftOkAction(managesSavedGift: false, isListed: true, ownerAccess: .doesNotManage), .buy)
        XCTAssertEqual(uniqueGiftOkAction(managesSavedGift: false, isListed: true, ownerAccess: .manages), .close)
        XCTAssertEqual(uniqueGiftOkAction(managesSavedGift: false, isListed: true, ownerAccess: .unknown), .close)
    }

    func testUnlistedGiftOnlyCloses() {
        XCTAssertEqual(uniqueGiftOkAction(managesSavedGift: false, isListed: false, ownerAccess: .doesNotManage), .close)
    }
}
