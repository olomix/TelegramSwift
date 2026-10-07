import Foundation

/// Hides the cursor after an idle delay while a view is shown, and
/// shows it again when the view loses focus or goes away.
///
/// `schedule` runs its argument once after the idle delay and returns a
/// function that cancels it.
public final class CursorIdleController {
    public typealias Cancel = () -> Void
    public typealias Scheduler = (@escaping () -> Void) -> Cancel

    private let hider: CursorHider
    private let schedule: Scheduler
    private var cancelPendingIdle: Cancel?

    private(set) var isAppeared = false

    var isCursorHidden: Bool {
        return hider.isHidden
    }

    var hasPendingIdle: Bool {
        return cancelPendingIdle != nil
    }

    public init(hide: @escaping () -> Void,
                unhide: @escaping () -> Void,
                schedule: @escaping Scheduler) {
        self.hider = CursorHider(hide: hide, unhide: unhide)
        self.schedule = schedule
    }

    deinit {
        cancelPendingIdle?()
    }

    /// Marks the view as shown; `rearm` starts the idle delay.
    public func appear() {
        isAppeared = true
    }

    /// Shows the cursor; later `rearm` calls do nothing until `appear`.
    public func endAppearance() {
        isAppeared = false
        showCursor()
    }

    /// Cancels the pending idle callback and shows the cursor.
    public func showCursor() {
        cancelPendingIdle?()
        cancelPendingIdle = nil
        hider.show()
    }

    /// Shows the cursor and, while appeared, restarts the idle delay.
    /// `onIdle` runs once the delay passes without another rearm.
    public func rearm(onIdle: @escaping () -> Void) {
        showCursor()
        guard isAppeared else { return }
        cancelPendingIdle = schedule { [weak self] in
            self?.cancelPendingIdle = nil
            onIdle()
        }
    }

    /// Hides the cursor while appeared if `conditions` allow it.
    public func hideIfIdle(_ conditions: CursorIdleConditions) {
        if isAppeared && shouldHideCursorOnIdle(conditions) {
            hider.hide()
        }
    }
}
