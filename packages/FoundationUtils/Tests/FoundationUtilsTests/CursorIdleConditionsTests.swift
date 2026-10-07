import XCTest
@testable import FoundationUtils

extension CursorIdleConditions {
    static let idle = CursorIdleConditions(
        isWindowVisible: true,
        isWindowKey: true,
        isAppActive: true,
        isMouseInside: true,
        isPointerNeeded: false)
}

final class ShouldHideCursorOnIdleTests: XCTestCase {
    private let allGood = CursorIdleConditions.idle

    func testAllGoodHides() {
        XCTAssertTrue(shouldHideCursorOnIdle(allGood))
    }

    func testEachFailingConditionKeepsCursorVisible() {
        let breakers: [(String, (inout CursorIdleConditions) -> Void)] = [
            ("window hidden", { $0.isWindowVisible = false }),
            ("window not key", { $0.isWindowKey = false }),
            ("app inactive", { $0.isAppActive = false }),
            ("mouse outside", { $0.isMouseInside = false }),
            ("pointer needed", { $0.isPointerNeeded = true }),
        ]
        XCTAssertEqual(breakers.count, Mirror(reflecting: allGood).children.count,
                       "every condition needs a breaker")
        for (name, breakCondition) in breakers {
            var conditions = allGood
            breakCondition(&conditions)
            XCTAssertFalse(shouldHideCursorOnIdle(conditions), name)
        }
    }
}
