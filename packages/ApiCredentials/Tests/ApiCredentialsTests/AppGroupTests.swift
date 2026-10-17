import XCTest
@testable import ApiCredentials

final class AppGroupTests: XCTestCase {
    func testTeamPrefixedIdentifierIsAccepted() {
        XCTAssertTrue(AppGroup.isTeamPrefixed("3PB2Z94Q5T.com.korthane.telex"))
    }

    func testIdentifierWithoutTeamIsRejected() {
        XCTAssertFalse(AppGroup.isTeamPrefixed("com.korthane.telex"))
        XCTAssertFalse(AppGroup.isTeamPrefixed(".com.korthane.telex"))
        XCTAssertFalse(AppGroup.isTeamPrefixed(""))
    }

    func testLowerCasePrefixIsRejected() {
        XCTAssertFalse(AppGroup.isTeamPrefixed("3pb2z94q5t.com.korthane.telex"))
    }

    func testShortOrLongPrefixIsRejected() {
        XCTAssertFalse(AppGroup.isTeamPrefixed("3PB2Z94Q5.com.korthane.telex"))
        XCTAssertFalse(AppGroup.isTeamPrefixed("3PB2Z94Q5TX.com.korthane.telex"))
    }

    func testUnexpandedBuildVariableIsRejected() {
        XCTAssertFalse(AppGroup.isTeamPrefixed("$(TeamIdentifierPrefix)com.korthane.telex"))
    }
}
