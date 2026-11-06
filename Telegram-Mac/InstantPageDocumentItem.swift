//
//  InstantPageDocumentItem.swift
//  Telegram
//

import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore

private let statusDiameter: CGFloat = 40.0
private let statusToTextSpacing: CGFloat = 10.0

final class InstantPageDocumentItem: InstantPageItem {
    static let height: CGFloat = 52.0

    var frame: CGRect
    let file: TelegramMediaFile
    let webpage: TelegramMediaWebpage
    let horizontalInset: CGFloat
    let pageTheme: InstantPageTheme
    let hasLinks: Bool = false
    let wantsView: Bool = true
    // Empty so the file stays out of the page's media gallery.
    let medias: [InstantPageMedia] = []
    let separatesTiles: Bool = false
    // The click handler needs a media on interactive items.
    let isInteractive: Bool = false

    init(frame: CGRect, file: TelegramMediaFile, webpage: TelegramMediaWebpage, horizontalInset: CGFloat, pageTheme: InstantPageTheme) {
        self.frame = frame
        self.file = file
        self.webpage = webpage
        self.horizontalInset = horizontalInset
        self.pageTheme = pageTheme
    }

    func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }

    func drawInTile(context: CGContext) {
    }

    func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        return InstantPageDocumentView(item: self, context: arguments.context)
    }

    // Reuse across resizes keeps a pending open; a theme change needs new colours.
    func matchesView(_ node: InstantPageView) -> Bool {
        guard let view = node as? InstantPageDocumentView else {
            return false
        }
        return view.item.file.fileId == file.fileId && view.item.pageTheme.type == pageTheme.type
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

private final class InstantPageDocumentView: Control, InstantPageClickableView {
    let item: InstantPageDocumentItem
    private let context: AccountContext
    private let statusView: RadialProgressView
    private let nameView = TextView()
    private let sizeView = TextView()
    private let statusDisposable = MetaDisposable()
    private var status: MediaResourceStatus?
    private var opensWhenFetched = false

    init(item: InstantPageDocumentItem, context: AccountContext) {
        self.item = item
        self.context = context
        let pageTheme = item.pageTheme
        self.statusView = RadialProgressView(theme: RadialProgressTheme(backgroundColor: pageTheme.linkColor, foregroundColor: theme.colors.underSelectedColor), size: NSMakeSize(statusDiameter, statusDiameter))
        super.init(frame: item.frame)

        statusView.isEventLess = true
        addSubview(statusView)

        let file = item.file
        let name = NSAttributedString.initialize(string: file.fileName ?? strings().storageUsageMediaFile, color: pageTheme.panelPrimaryColor, font: .medium(.title))
        // Keep the extension visible when a long name is cut.
        configure(nameView, layout: TextViewLayout(name, maximumNumberOfLines: 1, truncationType: .middle))
        let size = file.size.map { String.prettySized(with: $0) } ?? ""
        configure(sizeView, layout: TextViewLayout(.initialize(string: size, color: pageTheme.panelSecondaryColor, font: .normal(.text)), maximumNumberOfLines: 1))

        set(background: .clear, for: .Normal)
        set(background: pageTheme.panelHighlightedBackgroundColor, for: .Highlight)
        set(handler: { [weak self] _ in
            self?.handleClick()
        }, for: .Click)

        statusDisposable.set((context.account.postbox.mediaBox.resourceStatus(file.resource) |> deliverOnMainQueue).start(next: { [weak self] status in
            self?.apply(status: status)
        }))
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        statusDisposable.dispose()
    }

    private func configure(_ textView: TextView, layout: TextViewLayout) {
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.isEventLess = true
        textView.set(layout: layout)
        addSubview(textView)
    }

    override func layout() {
        super.layout()
        let textX = item.horizontalInset + statusDiameter + statusToTextSpacing
        let textWidth = max(1.0, bounds.width - textX - item.horizontalInset)
        nameView.textLayout?.measure(width: textWidth)
        sizeView.textLayout?.measure(width: textWidth)
        nameView.update(nameView.textLayout)
        sizeView.update(sizeView.textLayout)

        statusView.centerY(x: item.horizontalInset)
        let textHeight = nameView.frame.height + sizeView.frame.height
        let top = floorToScreenPixels(backingScaleFactor, (bounds.height - textHeight) / 2.0)
        nameView.setFrameOrigin(NSMakePoint(textX, top))
        sizeView.setFrameOrigin(NSMakePoint(textX, nameView.frame.maxY))
    }

    func updateIsVisible(_ isVisible: Bool) {
    }

    private func apply(status: MediaResourceStatus) {
        self.status = status
        switch status {
        case .Remote:
            statusView.state = .Remote
        case let .Fetching(_, progress), let .Paused(progress):
            statusView.state = .Fetching(progress: progress, force: false)
        case .Local:
            statusView.state = .Icon(image: theme.icons.chatFileThumb)
            if opensWhenFetched {
                opensWhenFetched = false
                open()
            }
        }
    }

    private func handleClick() {
        guard let status = status else {
            return
        }
        switch status {
        case .Local:
            open()
        case .Fetching:
            opensWhenFetched = false
            cancelFreeMediaFileInteractiveFetch(context: context, resource: item.file.resource)
        case .Remote, .Paused:
            opensWhenFetched = true
            // Not tied to the view: scrolling the row away shouldn't drop a
            // download the user asked for. Cancel goes through the media box.
            let reference = FileMediaReference.webPage(webPage: WebpageReference(item.webpage), media: item.file)
            _ = freeMediaFileInteractiveFetched(context: context, fileReference: reference).start()
        }
    }

    private func open() {
        QuickLookPreview.current.showAfterWarningIfRisky(context: context, with: item.file, stableId: nil, window: (window as? Window) ?? context.window)
    }
}
