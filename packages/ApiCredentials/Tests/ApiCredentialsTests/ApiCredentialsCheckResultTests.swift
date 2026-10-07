import XCTest
@testable import ApiCredentials

final class ApiCredentialsCheckResultTests: XCTestCase {
    func testApiIdErrorsReject() {
        XCTAssertEqual(ApiCredentialsCheckResult(serverError: "API_ID_INVALID"), .rejected)
        XCTAssertEqual(ApiCredentialsCheckResult(serverError: "API_ID_PUBLISHED_FLOOD"), .rejected)
    }

    func testOtherServerErrorsAreUnreachable() {
        for error in ["INTERNAL", "Timeout", "AUTH_RESTART", "SESSION_PASSWORD_NEEDED", "FLOOD_WAIT_30", ""] {
            XCTAssertEqual(ApiCredentialsCheckResult(serverError: error), .unreachable, error)
        }
    }
}
