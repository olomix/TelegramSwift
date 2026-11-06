import XCTest
@testable import FoundationUtils

final class PillRowLayoutTests: XCTestCase {
    private func origins(_ frames: [CGRect]) -> [CGPoint] {
        return frames.map { $0.origin }
    }

    func testLeftAlignmentStartsAtZero() {
        let frames = huggingPillFrames(widths: [50, 30], alignment: .left, availableWidth: 200, rtl: false)
        XCTAssertEqual(origins(frames), [CGPoint(x: 0, y: 0), CGPoint(x: 56, y: 0)])
    }

    func testRightAlignmentEndsAtTheEdge() {
        let frames = huggingPillFrames(widths: [50, 30], alignment: .right, availableWidth: 200, rtl: false)
        XCTAssertEqual(origins(frames), [CGPoint(x: 114, y: 0), CGPoint(x: 170, y: 0)])
    }

    func testCenterAlignmentSplitsTheSlack() {
        let frames = huggingPillFrames(widths: [50, 30], alignment: .center, availableWidth: 200, rtl: false)
        XCTAssertEqual(origins(frames), [CGPoint(x: 57, y: 0), CGPoint(x: 113, y: 0)])
    }

    func testRtlLeftStartsAtTheRightEdgeWithFirstPillOutermost() {
        let frames = huggingPillFrames(widths: [50, 30], alignment: .left, availableWidth: 200, rtl: true)
        XCTAssertEqual(origins(frames), [CGPoint(x: 150, y: 0), CGPoint(x: 114, y: 0)])
    }

    func testRtlRightStartsAtZeroWithFirstPillOnTheRight() {
        let frames = huggingPillFrames(widths: [50, 30], alignment: .right, availableWidth: 200, rtl: true)
        XCTAssertEqual(origins(frames), [CGPoint(x: 36, y: 0), CGPoint(x: 0, y: 0)])
    }

    func testRtlCenterMirrorsTheOrder() {
        let frames = huggingPillFrames(widths: [50, 30], alignment: .center, availableWidth: 200, rtl: true)
        XCTAssertEqual(origins(frames), [CGPoint(x: 93, y: 0), CGPoint(x: 57, y: 0)])
    }

    func testPillsWrapWhenTheRowIsFull() {
        let frames = huggingPillFrames(widths: [60, 60, 60], alignment: .left, availableWidth: 130, rtl: false)
        XCTAssertEqual(origins(frames), [CGPoint(x: 0, y: 0), CGPoint(x: 66, y: 0), CGPoint(x: 0, y: 46)])
    }

    func testHuggingRowHoldsAtMostEightPills() {
        let frames = huggingPillFrames(widths: Array(repeating: 10, count: 9), alignment: .left, availableWidth: 1000, rtl: false)
        XCTAssertEqual(frames[7].minY, 0)
        XCTAssertEqual(frames[8].minY, 46)
        XCTAssertEqual(frames[8].minX, 0)
    }

    func testPillWiderThanTheRowKeepsItsOwnRowWithNoNegativeSlack() {
        let frames = huggingPillFrames(widths: [300, 50], alignment: .right, availableWidth: 200, rtl: false)
        XCTAssertEqual(origins(frames), [CGPoint(x: 0, y: 0), CGPoint(x: 150, y: 46)])
    }

    func testNoPillsGiveNoFrames() {
        XCTAssertTrue(huggingPillFrames(widths: [], alignment: .left, availableWidth: 200, rtl: false).isEmpty)
        XCTAssertTrue(justifiedPillFrames(count: 0, availableWidth: 200, rtl: false).isEmpty)
    }

    func testJustifiedPillsShareTheWidth() {
        let frames = justifiedPillFrames(count: 2, availableWidth: 206, rtl: false)
        XCTAssertEqual(frames, [CGRect(x: 0, y: 0, width: 100, height: 40), CGRect(x: 106, y: 0, width: 100, height: 40)])
    }

    func testJustifiedRtlMirrorsTheOrder() {
        let frames = justifiedPillFrames(count: 2, availableWidth: 206, rtl: true)
        XCTAssertEqual(frames.map { $0.minX }, [106, 0])
    }

    func testJustifiedRowHoldsAtMostEightPills() {
        let frames = justifiedPillFrames(count: 9, availableWidth: 2000, rtl: false)
        XCTAssertEqual(frames[7].minY, 0)
        XCTAssertEqual(frames[8].minY, 46)
        XCTAssertEqual(frames[8].width, 2000)
    }

    func testJustifiedWidthBelowOneColumnStacksPills() {
        let frames = justifiedPillFrames(count: 2, availableWidth: 60, rtl: false)
        XCTAssertEqual(frames, [CGRect(x: 0, y: 0, width: 60, height: 40), CGRect(x: 0, y: 46, width: 60, height: 40)])
    }

    func testJustifiedShorterLastRowFillsTheWidth() {
        // 172 fits two 80pt columns.
        let frames = justifiedPillFrames(count: 3, availableWidth: 172, rtl: false)
        XCTAssertEqual(frames[0].width, 83)
        XCTAssertEqual(frames[2].width, 172)
        XCTAssertEqual(frames[2].minY, 46)
    }
}
