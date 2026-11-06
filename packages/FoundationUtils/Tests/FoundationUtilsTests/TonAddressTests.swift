import XCTest
@testable import FoundationUtils

final class TonAddressTests: XCTestCase {
    private let standard = "EQDtFpEwcFAEcRe5mLVh2N6C0x+/xJ5uWsYKBk4OZ3a9zXYZ"
    private let urlSafe = "EQDtFpEwcFAEcRe5mLVh2N6C0x-_xJ5uWsYKBk4OZ3a9zXYZ"

    func testAcceptsStandardBase64Alphabet() {
        XCTAssertEqual(standard.count, 48)
        XCTAssertTrue(isValidTonAddress(standard))
    }

    func testAcceptsUrlSafeBase64Alphabet() {
        XCTAssertEqual(urlSafe.count, 48)
        XCTAssertTrue(isValidTonAddress(urlSafe))
    }

    func testAcceptsAlphanumericOnlyAddress() {
        XCTAssertTrue(isValidTonAddress(String(repeating: "aZ09", count: 12)))
    }

    func testRejectsEmptyString() {
        XCTAssertFalse(isValidTonAddress(""))
    }

    func testRejectsWrongLength() {
        XCTAssertFalse(isValidTonAddress(String(standard.dropLast())))
        XCTAssertFalse(isValidTonAddress(standard + "A"))
    }

    func testRejectsBadCharacters() {
        for bad in [" ", "=", ".", "!", "\n", "я"] {
            let address = String(standard.dropLast()) + bad
            XCTAssertFalse(isValidTonAddress(address), "accepted \(bad)")
        }
    }

    // One Character but several UTF-8 bytes, so counting either way must fail.
    func testRejectsCombiningCharacters() {
        let address = String(standard.dropLast()) + "A\u{301}"
        XCTAssertEqual(address.count, 48)
        XCTAssertFalse(isValidTonAddress(address))
    }

    func testRejectsMixedAlphabets() {
        let mixed = "EQDtFpEwcFAEcRe5mLVh2N6C0x+_xJ5uWsYKBk4OZ3a9zXYZ"
        XCTAssertEqual(mixed.count, 48)
        XCTAssertFalse(isValidTonAddress(mixed))
    }
}
