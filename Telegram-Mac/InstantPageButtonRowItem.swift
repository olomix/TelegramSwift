//
//  InstantPageButtonRowItem.swift
//  Telegram
//

import Cocoa
import TGUIKit
import TelegramCore
import FoundationUtils

let instantPageButtonRowFontSize: CGFloat = 16.0

private let comfortablePillPadding: CGFloat = 19.0
private let tightPillPadding: CGFloat = 6.0

private func comfortablePadding(for button: InstantPageButton) -> CGFloat {
    // A link button has no fill, so its label sits flush and reads as a link.
    return button.isLink ? 0.0 : comfortablePillPadding
}

private func pillColors(for button: InstantPageButton, pageTheme: InstantPageTheme) -> (fill: NSColor, label: NSColor) {
    let fill: NSColor
    let label: NSColor
    if button.isLink {
        fill = .clear
        label = pageTheme.linkColor
    } else {
        switch button.color {
        case .none:
            fill = pageTheme.panelBackgroundColor
            label = pageTheme.panelPrimaryColor
        case .primary:
            fill = theme.colors.accent
            label = theme.colors.underSelectedColor
        case .danger:
            fill = theme.colors.redUI
            label = theme.colors.underSelectedColor
        case .success:
            fill = theme.colors.greenUI
            label = theme.colors.underSelectedColor
        }
    }
    return (fill, button.action == .disabled ? label.withAlphaComponent(0.4) : label)
}

private func pillRowAlignment(_ alignment: InstantPageButtonRowAlignment) -> PillRowAlignment {
    switch alignment {
    case .left:
        return .left
    case .center:
        return .center
    case .right:
        return .right
    case .justify:
        return .justify
    }
}

/// Lays out a button row block, or returns nil when it would show nothing.
func layoutInstantPageButtonRow(labelledButtons: [(button: InstantPageButton, label: NSAttributedString)], alignment: InstantPageButtonRowAlignment, boundingWidth: CGFloat, horizontalInset: CGFloat, rtl: Bool, pageTheme: InstantPageTheme) -> InstantPageButtonRowItem? {
    let availableWidth = boundingWidth - horizontalInset * 2.0
    guard !labelledButtons.isEmpty, availableWidth > 0.0 else {
        return nil
    }

    let colors = labelledButtons.map { pillColors(for: $0.button, pageTheme: pageTheme) }
    let labels = labelledButtons.enumerated().map { index, entry -> TextViewLayout in
        let label = NSMutableAttributedString(attributedString: entry.label)
        // Keep nested links readable on the fill.
        label.addAttribute(.foregroundColor, value: colors[index].label, range: NSMakeRange(0, label.length))
        let layout = TextViewLayout(label, maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        return layout
    }
    let naturalWidths = labels.map { $0.layoutSize.width }

    let frames: [CGRect]
    if alignment == .justify {
        frames = justifiedPillFrames(count: labels.count, availableWidth: availableWidth, rtl: rtl)
    } else {
        let widths = labelledButtons.indices.map { index in
            min(availableWidth, naturalWidths[index] + comfortablePadding(for: labelledButtons[index].button) * 2.0)
        }
        frames = huggingPillFrames(widths: widths, alignment: pillRowAlignment(alignment), availableWidth: availableWidth, rtl: rtl)
    }

    let pills = labelledButtons.indices.map { index -> InstantPageButtonRowItem.Pill in
        let button = labelledButtons[index].button
        let comfortable = comfortablePadding(for: button)
        let width = frames[index].width
        // Padding is a preference: give it back before cutting the label.
        let padding = naturalWidths[index] + comfortable * 2.0 <= width ? comfortable : min(comfortable, tightPillPadding)
        let labelWidth = max(1.0, width - padding * 2.0)
        if labelWidth < naturalWidths[index] {
            labels[index].measure(width: labelWidth)
        }
        return InstantPageButtonRowItem.Pill(button: button, label: labels[index], fill: colors[index].fill, frame: frames[index].offsetBy(dx: horizontalInset, dy: 0.0).integral)
    }
    let height = frames.map { $0.maxY }.max() ?? 0.0
    return InstantPageButtonRowItem(frame: CGRect(x: 0.0, y: 0.0, width: boundingWidth, height: height), pills: pills)
}

final class InstantPageButtonRowItem: InstantPageItem {
    struct Pill {
        let button: InstantPageButton
        let label: TextViewLayout
        let fill: NSColor
        let frame: CGRect
    }

    var frame: CGRect
    let pills: [Pill]
    let hasLinks: Bool = false
    let wantsView: Bool = true
    let medias: [InstantPageMedia] = []
    let separatesTiles: Bool = false
    // The click handler needs a media on interactive items.
    let isInteractive: Bool = false

    init(frame: CGRect, pills: [Pill]) {
        self.frame = frame
        self.pills = pills
    }

    func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }

    func drawInTile(context: CGContext) {
    }

    func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        return InstantPageButtonRowView(item: self, performAction: arguments.performButtonAction)
    }

    // Pill frames are fixed per layout, so a relayout needs a new view.
    func matchesView(_ node: InstantPageView) -> Bool {
        return (node as? InstantPageButtonRowView)?.item === self
    }

    func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }

    func distanceThresholdGroup() -> Int? {
        return nil
    }

    func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        return 0.0
    }
}

private final class InstantPageButtonRowView: View, InstantPageView {
    let item: InstantPageButtonRowItem

    init(item: InstantPageButtonRowItem, performAction: @escaping (InstantPageButton) -> Void) {
        self.item = item
        super.init(frame: item.frame)
        for pill in item.pills {
            addSubview(makePillControl(pill, performAction: performAction))
        }
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateIsVisible(_ isVisible: Bool) {
    }

    private func makePillControl(_ pill: InstantPageButtonRowItem.Pill, performAction: @escaping (InstantPageButton) -> Void) -> Control {
        let control = Control(frame: pill.frame)
        control.layer?.cornerRadius = pill.frame.height / 2.0
        control.set(background: pill.fill, for: .Normal)
        control.set(background: pill.fill.withAlphaComponent(pill.fill.alphaComponent * 0.85), for: .Highlight)
        control.scaleOnClick = true
        control.isEnabled = pill.button.action != .disabled
        control.set(handler: { _ in
            performAction(pill.button)
        }, for: .Click)

        let label = TextView()
        label.userInteractionEnabled = false
        label.isSelectable = false
        label.update(pill.label)
        control.addSubview(label)
        label.center()
        return control
    }
}
