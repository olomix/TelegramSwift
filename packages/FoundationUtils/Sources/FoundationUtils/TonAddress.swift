import Foundation

/// Whether `address` has the shape of a user-friendly TON address: exactly 48
/// characters, all from the standard or all from the URL-safe base64 alphabet.
///
/// The checksum is deliberately not verified: addresses are only copied, and a
/// stricter rule could wrongly reject real ones.
public func isValidTonAddress(_ address: String) -> Bool {
    let bytes = Array(address.utf8)
    guard bytes.count == 48 else {
        return false
    }
    let isBase64Core: (UInt8) -> Bool = { byte in
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        default:
            return false
        }
    }
    let usesStandardAlphabet = bytes.allSatisfy {
        isBase64Core($0) || $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: "/")
    }
    let usesUrlSafeAlphabet = bytes.allSatisfy {
        isBase64Core($0) || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "_")
    }
    return usesStandardAlphabet || usesUrlSafeAlphabet
}
