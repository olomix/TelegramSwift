import XCTest
@testable import ApiCredentials

final class ApiCredentialsValuesTests: XCTestCase {
    private let validHash = "0123456789abcdef0123456789abcdef"

    private func invalidFields(apiId: String, apiHash: String) -> Set<ApiCredentialsField>? {
        switch ApiCredentialsValues.validate(apiId: apiId, apiHash: apiHash) {
        case .success:
            return nil
        case let .failure(error):
            return error.invalidFields
        }
    }

    func testValidInput() {
        let result = ApiCredentialsValues.validate(apiId: "12345", apiHash: validHash)
        XCTAssertEqual(try result.get(), ApiCredentialsValues(apiId: 12345, apiHash: validHash))
    }

    func testTrimsWhitespaceAndLowercasesHash() {
        let result = ApiCredentialsValues.validate(apiId: "  12345\n", apiHash: " \t0123456789ABCDEF0123456789AbCdEf \n")
        XCTAssertEqual(try result.get(), ApiCredentialsValues(apiId: 12345, apiHash: validHash))
    }

    func testAcceptsMaxInt32() {
        let result = ApiCredentialsValues.validate(apiId: "2147483647", apiHash: validHash)
        XCTAssertEqual(try result.get().apiId, Int32.max)
    }

    func testRejectsBadApiId() {
        for id in ["", "   ", "0", "-5", "abc", "12a", "+12", "1.5", "2147483648", "99999999999999999999", "١٢٣", "１２３"] {
            XCTAssertEqual(invalidFields(apiId: id, apiHash: validHash), [.apiId], "api_id \(id.debugDescription)")
        }
    }

    func testRejectsBadApiHash() {
        let hashes = [
            "",
            String(validHash.dropLast()),
            validHash + "0",
            "0123456789abcdef0123456789abcdeg",
            "0123456789abcdef 123456789abcdef",
            "0123456789abcdef0123456789abcdeＡ",
        ]
        for hash in hashes {
            XCTAssertEqual(invalidFields(apiId: "12345", apiHash: hash), [.apiHash], "api_hash \(hash.debugDescription)")
        }
    }

    func testReportsBothFieldsWhenBothAreBad() {
        XCTAssertEqual(invalidFields(apiId: "", apiHash: ""), [.apiId, .apiHash])
    }
}
