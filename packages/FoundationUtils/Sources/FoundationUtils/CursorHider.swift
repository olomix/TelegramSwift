import Foundation

/// Owns at most one hide of the system cursor.
///
/// The system hide counter is per-app, so an unbalanced hide keeps the
/// cursor invisible whenever the app is frontmost. `hide()` and `show()`
/// are idempotent, and a held hide is released on deinit.
public final class CursorHider {
    private let hideCursor: () -> Void
    private let unhideCursor: () -> Void

    private(set) var isHidden: Bool = false

    public init(hide: @escaping () -> Void, unhide: @escaping () -> Void) {
        self.hideCursor = hide
        self.unhideCursor = unhide
    }

    deinit {
        show()
    }

    public func hide() {
        guard !isHidden else { return }
        isHidden = true
        hideCursor()
    }

    public func show() {
        guard isHidden else { return }
        isHidden = false
        unhideCursor()
    }
}
