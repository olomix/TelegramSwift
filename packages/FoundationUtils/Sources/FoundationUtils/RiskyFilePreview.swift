import Foundation

private let riskyExtensions: Set<String> = [
    "sh", "bash", "zsh", "csh", "tcsh", "command", "svg", "html", "htm", "xhtml",
    "app", "exe", "bin", "run", "pkg", "mpkg", "dmg", "iso", "docm", "xlsm", "pptm",
    "alias", "lnk", "plist", "conf", "ini",
]

private let riskyMimeTypes: Set<String> = [
    "text/html", "application/xhtml+xml", "image/svg+xml",
    "application/x-sh", "application/x-csh", "application/x-executable",
    "application/x-msdownload", "application/x-msdos-program",
    "application/x-apple-diskimage", "application/x-iso9660-image",
    "application/vnd.apple.installer+xml", "application/x-newton-compatible-pkg",
    "application/vnd.ms-word.document.macroenabled.12",
    "application/vnd.ms-excel.sheet.macroenabled.12",
    "application/vnd.ms-powerpoint.presentation.macroenabled.12",
]

/// Whether opening a file could run code or mislead, so the user should be
/// warned first. Only the last extension counts: `x.html.txt` opens as text.
/// The name and the MIME type come from the sender, so either one is enough.
public func isRiskyToPreview(fileName: String?, mimeType: String) -> Bool {
    let name = (fileName ?? "").lowercased()
    if riskyExtensions.contains(where: { name.hasSuffix("." + $0) }) {
        return true
    }
    // Parameters such as "; charset=utf-8" don't change the type.
    let essence = mimeType.prefix(while: { $0 != ";" }).trimmingCharacters(in: .whitespaces).lowercased()
    return riskyMimeTypes.contains(essence) || riskyExtensions.contains(essence)
}
