import XCTest
@testable import FoundationUtils

final class RiskyFilePreviewTests: XCTestCase {
    func testRiskyExtensionWarnsInAnyCase() {
        XCTAssertTrue(isRiskyToPreview(fileName: "x.html", mimeType: "text/plain"))
        XCTAssertTrue(isRiskyToPreview(fileName: "PAYLOAD.COMMAND", mimeType: "text/plain"))
        XCTAssertTrue(isRiskyToPreview(fileName: "x.Svg", mimeType: "text/plain"))
        XCTAssertTrue(isRiskyToPreview(fileName: ".html", mimeType: "text/plain"))
    }

    func testOnlyTheLastExtensionCounts() {
        XCTAssertTrue(isRiskyToPreview(fileName: "x.txt.html", mimeType: "text/plain"))
        XCTAssertFalse(isRiskyToPreview(fileName: "x.html.txt", mimeType: "text/plain"))
    }

    func testNameWithoutRiskyExtensionIsSafe() {
        XCTAssertFalse(isRiskyToPreview(fileName: "report.pdf", mimeType: "application/pdf"))
        XCTAssertFalse(isRiskyToPreview(fileName: "html", mimeType: "text/plain"))
        XCTAssertFalse(isRiskyToPreview(fileName: "", mimeType: "text/plain"))
    }

    func testNamelessFileIsJudgedByMimeType() {
        XCTAssertFalse(isRiskyToPreview(fileName: nil, mimeType: "image/png"))
        XCTAssertTrue(isRiskyToPreview(fileName: nil, mimeType: "text/html"))
        XCTAssertTrue(isRiskyToPreview(fileName: nil, mimeType: "image/svg+xml"))
    }

    func testMimeTypeIgnoresCaseAndParameters() {
        XCTAssertTrue(isRiskyToPreview(fileName: nil, mimeType: "TEXT/HTML"))
        XCTAssertTrue(isRiskyToPreview(fileName: nil, mimeType: "text/html; charset=utf-8"))
    }

    func testRiskyMimeTypeWarnsDespiteSafeName() {
        XCTAssertTrue(isRiskyToPreview(fileName: "photo.jpg", mimeType: "text/html"))
    }

    // The old check compared the MIME type with extensions; keep that case warning.
    func testBareExtensionAsMimeTypeWarns() {
        XCTAssertTrue(isRiskyToPreview(fileName: nil, mimeType: "html"))
    }
}
