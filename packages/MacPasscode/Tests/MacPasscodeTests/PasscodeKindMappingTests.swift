import PasscodeCore
import XCTest
@testable import MacPasscode

final class PasscodeKindMappingTests: XCTestCase {
    func testAsciiDigits() {
        XCTAssertEqual(PasscodeKindMapping.kind(for: "1234"), .digits4)
        XCTAssertEqual(PasscodeKindMapping.kind(for: "000000"), .digits6)
    }

    func testOtherLengthsAreAlphanumeric() {
        XCTAssertEqual(PasscodeKindMapping.kind(for: "123"), .alphanumeric)
        XCTAssertEqual(PasscodeKindMapping.kind(for: "12345"), .alphanumeric)
        XCTAssertEqual(PasscodeKindMapping.kind(for: "1234567"), .alphanumeric)
        XCTAssertEqual(PasscodeKindMapping.kind(for: ""), .alphanumeric)
    }

    func testMixedCodesAreAlphanumeric() {
        XCTAssertEqual(PasscodeKindMapping.kind(for: "12a4"), .alphanumeric)
        XCTAssertEqual(PasscodeKindMapping.kind(for: "12 4"), .alphanumeric)
        XCTAssertEqual(PasscodeKindMapping.kind(for: "pass"), .alphanumeric)
    }

    func testNonAsciiDigitsAreNormalized() {
        // Arabic-Indic, Devanagari and fullwidth digits.
        XCTAssertEqual(PasscodeKindMapping.kind(for: "\u{0661}\u{0662}\u{0663}\u{0664}"), .digits4)
        XCTAssertEqual(PasscodeKindMapping.kind(for: "\u{0967}\u{0968}\u{0969}\u{096A}\u{096B}\u{096C}"), .digits6)
        XCTAssertEqual(PasscodeKindMapping.kind(for: "\u{FF11}\u{FF12}3\u{FF14}"), .digits4)
    }

    func testNumeralsWithoutDigitValueAreAlphanumeric() {
        // Roman numeral twelve and a vulgar fraction have no 0-9 value.
        XCTAssertEqual(PasscodeKindMapping.kind(for: "1\u{216B}34"), .alphanumeric)
        XCTAssertEqual(PasscodeKindMapping.kind(for: "1\u{00BD}34"), .alphanumeric)
    }

    func testMappedCodeIsAcceptedByCoreRules() {
        for code in ["1234", "123456", "\u{0661}\u{0662}\u{0663}\u{0664}"] {
            let kind = PasscodeKindMapping.kind(for: code)
            let normalized = kind.normalize(code)
            XCTAssertTrue(normalized.allSatisfy { $0.isASCII && $0.isNumber }, code)
            XCTAssertEqual(normalized.count, kind == .digits6 ? 6 : 4, code)
        }
    }
}
