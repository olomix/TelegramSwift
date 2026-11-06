import Foundation

/// Whether `address` has the shape of a user-friendly TON address: exactly 48
/// characters, all from the standard or all from the URL-safe base64 alphabet.
///
/// The checksum is deliberately not verified: addresses are only copied, and a
/// stricter rule could wrongly reject real ones.
public func isValidTonAddress(_ address: String) -> Bool {
    // \z, not $: $ would also accept a trailing newline.
    return address.range(of: #"\A(?:[A-Za-z0-9+/]{48}|[A-Za-z0-9_-]{48})\z"#, options: .regularExpression) != nil
}
