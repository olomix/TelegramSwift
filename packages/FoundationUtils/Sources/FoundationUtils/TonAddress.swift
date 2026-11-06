import Foundation

/// Whether `address` has the shape of a user-friendly TON address. Addresses
/// are only copied, so the checksum goes unverified: it could reject real ones.
public func isValidTonAddress(_ address: String) -> Bool {
    // \z, not $: $ would also accept a trailing newline.
    return address.range(of: #"\A(?:[A-Za-z0-9+/]{48}|[A-Za-z0-9_-]{48})\z"#, options: .regularExpression) != nil
}
