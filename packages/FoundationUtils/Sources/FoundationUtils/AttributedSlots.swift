import Foundation

/// Replaces each slot's first occurrence in `format`, never in a replacement.
/// A slot the format lacks is skipped: language packs may drop arguments.
public func fillingSlots(in format: NSAttributedString, replacements: [(slot: String, value: NSAttributedString)]) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: format)
    let located = replacements
        .map { (range: (format.string as NSString).range(of: $0.slot), value: $0.value) }
        .filter { $0.range.location != NSNotFound }
        .sorted(by: { $0.range.location > $1.range.location })
    // Back to front, so earlier ranges stay valid.
    for item in located {
        result.replaceCharacters(in: item.range, with: item.value)
    }
    return result
}
