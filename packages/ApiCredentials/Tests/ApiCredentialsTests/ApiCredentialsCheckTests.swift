import XCTest
@testable import ApiCredentials

final class ApiCredentialsCheckTests: XCTestCase {
    func testOutcomeMapping() {
        XCTAssertEqual(ApiCredentialsCheckOutcome.token.result, .accepted)
        XCTAssertEqual(ApiCredentialsCheckOutcome.serverError.result, .rejected)
        XCTAssertEqual(ApiCredentialsCheckOutcome.timedOut.result, .unreachable)
    }

    func testCheckTimeout() {
        XCTAssertEqual(ApiCredentialsCheckOutcome.checkTimeout, 15)
    }

    func testLaunchWithoutStoredValuesRequiresCredentialsFirst() {
        XCTAssertEqual(ApiCredentialsGate.launchDecision(stored: nil), .requireBeforeLaunch)
    }

    func testLaunchWithStoredValuesChecksInBackground() {
        let stored = ApiCredentialsValues(apiId: 12345, apiHash: "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(ApiCredentialsGate.launchDecision(stored: stored), .launchAndCheckInBackground)
    }

    func testRejectedBackgroundCheckBlocks() {
        XCTAssertEqual(ApiCredentialsGate.decision(afterBackgroundCheck: .rejected), .requireBlocking)
    }

    func testAcceptedOrUnreachableBackgroundCheckDoesNothing() {
        XCTAssertEqual(ApiCredentialsGate.decision(afterBackgroundCheck: .accepted), ApiCredentialsGate.BackgroundCheckDecision.none)
        XCTAssertEqual(ApiCredentialsGate.decision(afterBackgroundCheck: .unreachable), ApiCredentialsGate.BackgroundCheckDecision.none)
    }
}
