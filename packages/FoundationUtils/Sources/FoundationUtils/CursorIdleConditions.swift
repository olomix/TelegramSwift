import Foundation

/// State checked before hiding the cursor over a view on idle.
public struct CursorIdleConditions {
    public var isWindowVisible: Bool
    public var isWindowKey: Bool
    public var isAppActive: Bool
    public var isMouseInside: Bool
    public var isPointerNeeded: Bool

    public init(isWindowVisible: Bool,
                isWindowKey: Bool,
                isAppActive: Bool,
                isMouseInside: Bool,
                isPointerNeeded: Bool) {
        self.isWindowVisible = isWindowVisible
        self.isWindowKey = isWindowKey
        self.isAppActive = isAppActive
        self.isMouseInside = isMouseInside
        self.isPointerNeeded = isPointerNeeded
    }
}

/// Returns true only when the view's window is visible and focused in the
/// active app, the pointer is over the view, and nothing else needs it.
public func shouldHideCursorOnIdle(_ conditions: CursorIdleConditions) -> Bool {
    return conditions.isWindowVisible
        && conditions.isWindowKey
        && conditions.isAppActive
        && conditions.isMouseInside
        && !conditions.isPointerNeeded
}
