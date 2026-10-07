import XCTest
@testable import ApiCredentials

final class AppGroupTests: XCTestCase {
    func testTeamPrefixedIdentifierIsAccepted() {
        XCTAssertTrue(AppGroup.isTeamPrefixed("3PB2Z94Q5T.dev.alek.telegram"))
    }

    func testIdentifierWithoutTeamIsRejected() {
        XCTAssertFalse(AppGroup.isTeamPrefixed("dev.alek.telegram"))
        XCTAssertFalse(AppGroup.isTeamPrefixed(".dev.alek.telegram"))
        XCTAssertFalse(AppGroup.isTeamPrefixed(""))
    }

    func testLowerCasePrefixIsRejected() {
        XCTAssertFalse(AppGroup.isTeamPrefixed("3pb2z94q5t.dev.alek.telegram"))
    }

    func testShortOrLongPrefixIsRejected() {
        XCTAssertFalse(AppGroup.isTeamPrefixed("3PB2Z94Q5.dev.alek.telegram"))
        XCTAssertFalse(AppGroup.isTeamPrefixed("3PB2Z94Q5TX.dev.alek.telegram"))
    }

    func testUnexpandedBuildVariableIsRejected() {
        XCTAssertFalse(AppGroup.isTeamPrefixed("$(TeamIdentifierPrefix)dev.alek.telegram"))
    }
}
