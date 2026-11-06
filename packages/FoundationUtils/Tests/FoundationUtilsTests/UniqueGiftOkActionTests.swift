import XCTest
@testable import FoundationUtils

final class UniqueGiftOkActionTests: XCTestCase {
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
