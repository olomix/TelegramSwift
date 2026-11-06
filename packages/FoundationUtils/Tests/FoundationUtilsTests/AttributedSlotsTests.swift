import XCTest
@testable import FoundationUtils

final class AttributedSlotsTests: XCTestCase {
    private func text(_ string: String) -> NSAttributedString {
        return NSAttributedString(string: string)
    }

    func testReorderedSlots() {
        let result = fillingSlots(in: text("B then A"), replacements: [(slot: "A", value: text("first")), (slot: "B", value: text("second"))])
        XCTAssertEqual(result.string, "second then first")
    }

    func testMissingSlotIsSkipped() {
        let result = fillingSlots(in: text("only A"), replacements: [(slot: "A", value: text("x")), (slot: "Z", value: text("y"))])
        XCTAssertEqual(result.string, "only x")
    }

    func testReplacementContainingAnotherSlotStaysAsIs() {
        let result = fillingSlots(in: text("\u{E000} to \u{E001}"), replacements: [(slot: "\u{E000}", value: text("\u{E001}name")), (slot: "\u{E001}", value: text("other"))])
        XCTAssertEqual(result.string, "\u{E001}name to other")
    }

    func testReplacementKeepsItsAttributes() {
        let key = NSAttributedString.Key("test")
        let value = NSAttributedString(string: "note", attributes: [key: 1])
        let result = fillingSlots(in: text("say A now"), replacements: [(slot: "A", value: value)])
        XCTAssertEqual(result.string, "say note now")
        XCTAssertEqual(result.attribute(key, at: 4, effectiveRange: nil) as? Int, 1)
        XCTAssertNil(result.attribute(key, at: 8, effectiveRange: nil))
    }
}
