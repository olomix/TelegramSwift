import XCTest
@testable import FoundationUtils

final class CursorHiderTests: XCTestCase {
    private final class Counter {
        var hides = 0
        var unhides = 0
    }

    private func makeHider(_ counter: Counter) -> CursorHider {
        return CursorHider(hide: { counter.hides += 1 },
                           unhide: { counter.unhides += 1 })
    }

    func testRepeatedHideCallsHideOnce() {
        let counter = Counter()
        let hider = makeHider(counter)
        hider.hide()
        hider.hide()
        hider.hide()
        XCTAssertEqual(counter.hides, 1)
        XCTAssertEqual(counter.unhides, 0)
        XCTAssertTrue(hider.isHidden)
    }

    func testShowAfterHideCallsUnhideOnce() {
        let counter = Counter()
        let hider = makeHider(counter)
        hider.hide()
        hider.show()
        hider.show()
        XCTAssertEqual(counter.hides, 1)
        XCTAssertEqual(counter.unhides, 1)
        XCTAssertFalse(hider.isHidden)
    }

    func testShowWithoutHideIsNoOp() {
        let counter = Counter()
        let hider = makeHider(counter)
        hider.show()
        XCTAssertEqual(counter.hides, 0)
        XCTAssertEqual(counter.unhides, 0)
        XCTAssertFalse(hider.isHidden)
    }

    func testHideAgainAfterShowHidesAgain() {
        let counter = Counter()
        let hider = makeHider(counter)
        hider.hide()
        hider.show()
        hider.hide()
        XCTAssertEqual(counter.hides, 2)
        XCTAssertEqual(counter.unhides, 1)
        XCTAssertTrue(hider.isHidden)
    }

    func testDeinitReleasesHeldHide() {
        let counter = Counter()
        var hider: CursorHider? = makeHider(counter)
        weak var weakHider = hider
        hider?.hide()
        hider = nil
        XCTAssertNil(weakHider)
        XCTAssertEqual(counter.hides, 1)
        XCTAssertEqual(counter.unhides, 1)
    }

    func testDeinitAfterShowDoesNotUnhideAgain() {
        let counter = Counter()
        var hider: CursorHider? = makeHider(counter)
        weak var weakHider = hider
        hider?.hide()
        hider?.show()
        hider = nil
        XCTAssertNil(weakHider)
        XCTAssertEqual(counter.hides, 1)
        XCTAssertEqual(counter.unhides, 1)
    }

    func testDeinitWithoutHideCallsNothing() {
        let counter = Counter()
        var hider: CursorHider? = makeHider(counter)
        weak var weakHider = hider
        hider = nil
        XCTAssertNil(weakHider)
        XCTAssertEqual(counter.hides, 0)
        XCTAssertEqual(counter.unhides, 0)
    }
}
