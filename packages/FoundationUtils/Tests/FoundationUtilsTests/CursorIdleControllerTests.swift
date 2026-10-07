import XCTest
@testable import FoundationUtils

final class CursorIdleControllerTests: XCTestCase {
    private final class Recorder {
        var hides = 0
        var unhides = 0
        var scheduled = 0
        var cancels = 0
        var pending: (() -> Void)?

        func fire() {
            let task = pending
            pending = nil
            task?()
        }
    }

    private let idle = CursorIdleConditions.idle

    private func makeController(_ recorder: Recorder) -> CursorIdleController {
        return CursorIdleController(
            hide: { recorder.hides += 1 },
            unhide: { recorder.unhides += 1 },
            schedule: { task in
                recorder.scheduled += 1
                recorder.pending = task
                return {
                    recorder.cancels += 1
                    recorder.pending = nil
                }
            })
    }

    func testRearmWhileAppearedRunsOnIdleAfterDelay() {
        let recorder = Recorder()
        let controller = makeController(recorder)
        var idleRuns = 0
        controller.appear()
        controller.rearm { idleRuns += 1 }
        XCTAssertEqual(recorder.scheduled, 1)
        XCTAssertEqual(idleRuns, 0)
        recorder.fire()
        XCTAssertEqual(idleRuns, 1)
        XCTAssertFalse(controller.hasPendingIdle)
    }

    func testRearmBeforeAppearSchedulesNothing() {
        let recorder = Recorder()
        let controller = makeController(recorder)
        controller.rearm {}
        XCTAssertEqual(recorder.scheduled, 0)
    }

    func testRearmAfterEndAppearanceSchedulesNothing() {
        let recorder = Recorder()
        let controller = makeController(recorder)
        controller.appear()
        controller.endAppearance()
        controller.rearm {}
        XCTAssertEqual(recorder.scheduled, 0)
        XCTAssertFalse(controller.hasPendingIdle)
    }

    func testEndAppearanceCancelsPendingIdle() {
        let recorder = Recorder()
        let controller = makeController(recorder)
        var idleRuns = 0
        controller.appear()
        controller.rearm { idleRuns += 1 }
        controller.endAppearance()
        XCTAssertEqual(recorder.cancels, 1)
        recorder.fire()
        XCTAssertEqual(idleRuns, 0)
    }

    func testShowCursorCancelsPendingIdleAndKeepsAppearance() {
        let recorder = Recorder()
        let controller = makeController(recorder)
        controller.appear()
        controller.rearm {}
        controller.showCursor()
        XCTAssertEqual(recorder.cancels, 1)
        XCTAssertFalse(controller.hasPendingIdle)
        XCTAssertTrue(controller.isAppeared)
        controller.rearm {}
        XCTAssertEqual(recorder.scheduled, 2)
    }

    func testRearmShowsHiddenCursorFirst() {
        let recorder = Recorder()
        let controller = makeController(recorder)
        controller.appear()
        controller.hideIfIdle(idle)
        XCTAssertTrue(controller.isCursorHidden)
        controller.rearm {}
        XCTAssertFalse(controller.isCursorHidden)
        XCTAssertEqual(recorder.unhides, 1)
    }

    func testHideIfIdleBeforeAppearDoesNothing() {
        let recorder = Recorder()
        let controller = makeController(recorder)
        controller.hideIfIdle(idle)
        XCTAssertEqual(recorder.hides, 0)
    }

    func testHideIfIdleRespectsConditions() {
        let recorder = Recorder()
        let controller = makeController(recorder)
        var notKey = idle
        notKey.isWindowKey = false
        controller.appear()
        controller.hideIfIdle(notKey)
        XCTAssertEqual(recorder.hides, 0)
    }

    func testAppearIdleEndAppearanceIsBalanced() {
        let recorder = Recorder()
        let controller = makeController(recorder)
        controller.appear()
        controller.rearm { [unowned controller, idle] in
            controller.hideIfIdle(idle)
        }
        recorder.fire()
        controller.endAppearance()
        XCTAssertEqual(recorder.hides, 1)
        XCTAssertEqual(recorder.unhides, 1)
    }

    func testDeinitCancelsPendingIdleAndShowsCursor() {
        let recorder = Recorder()
        var controller: CursorIdleController? = makeController(recorder)
        weak var weakController = controller
        controller?.appear()
        controller?.hideIfIdle(idle)
        controller?.rearm {}
        controller?.hideIfIdle(idle)
        controller = nil
        XCTAssertNil(weakController)
        XCTAssertEqual(recorder.cancels, 1)
        XCTAssertEqual(recorder.hides, recorder.unhides)
    }
}
