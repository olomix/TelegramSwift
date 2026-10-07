import XCTest
@testable import ApiCredentials

final class ApiCredentialsFieldProblemTests: XCTestCase {
    private let validHash = "0123456789abcdef0123456789abcdef"

    func testValidInputHasNoProblems() {
        XCTAssertEqual(ApiCredentialsFieldProblem.formatProblems(apiId: "12345", apiHash: validHash), [:])
    }

    func testEmptyFieldsAreMissing() {
        XCTAssertEqual(ApiCredentialsFieldProblem.formatProblems(apiId: "", apiHash: ""), [.apiId: .missing, .apiHash: .missing])
    }

    func testWhitespaceOnlyIsMissing() {
        XCTAssertEqual(ApiCredentialsFieldProblem.formatProblems(apiId: "  ", apiHash: "\n"), [.apiId: .missing, .apiHash: .missing])
    }

    func testBadValuesAreMalformed() {
        XCTAssertEqual(ApiCredentialsFieldProblem.formatProblems(apiId: "abc", apiHash: "xyz"), [.apiId: .malformed, .apiHash: .malformed])
    }

    func testOnlyTheBadFieldIsReported() {
        XCTAssertEqual(ApiCredentialsFieldProblem.formatProblems(apiId: "0", apiHash: validHash), [.apiId: .malformed])
        XCTAssertEqual(ApiCredentialsFieldProblem.formatProblems(apiId: "12345", apiHash: ""), [.apiHash: .missing])
    }

    func testRejectedByServerMarksBothFields() {
        XCTAssertEqual(ApiCredentialsFieldProblem.rejectedByServer, [.apiId: .rejected, .apiHash: .rejected])
    }
}
