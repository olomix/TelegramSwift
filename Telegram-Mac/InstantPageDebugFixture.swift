//
//  InstantPageDebugFixture.swift
//  Telegram
//

#if DEBUG

import Foundation
import Postbox
import TelegramCore

// Real pages may lack these blocks, so this renders them from local values.
// It says nothing about what the server actually sends to Mac.

// Fixed IDs so reopening reuses the browser tab and the stored files.
private let ltrWebpageId = MediaId(namespace: Namespaces.Media.LocalWebpage, id: 0x7E1E_F1C7)
private let rtlWebpageId = MediaId(namespace: Namespaces.Media.LocalWebpage, id: 0x7E1E_F1CB)
private let storedDocumentId = MediaId(namespace: Namespaces.Media.LocalFile, id: 0x7E1E_F1C8)
private let unfetchableDocumentId = MediaId(namespace: Namespaces.Media.LocalFile, id: 0x7E1E_F1C9)
private let missingDocumentId = MediaId(namespace: Namespaces.Media.LocalFile, id: 0x7E1E_F1CA)
private let riskyDocumentId = MediaId(namespace: Namespaces.Media.LocalFile, id: 0x7E1E_F1CC)
private let namelessDocumentId = MediaId(namespace: Namespaces.Media.LocalFile, id: 0x7E1E_F1CD)
// The layout looks inline images up in this namespace.
private let inlineImageId = MediaId(namespace: Namespaces.Media.CloudFile, id: 0x7E1E_F1CE)

// .invalid never resolves: the page controller asks the server to refresh
// its URL.
private let ltrFixtureUrl = "https://telex.invalid/instant-page-fixture"
private let rtlFixtureUrl = "https://telex.invalid/instant-page-fixture-rtl"
// Passes isValidTonAddress but is no real wallet; a click copies it.
private let validTonAddress = "EQTelexInstantPageFixture_NotARealAddress-000000"
private let invalidTonAddress = "EQTooShortToBeAnAddress"

private func caption(_ text: String) -> InstantPageCaption {
    return InstantPageCaption(text: .plain(text), credit: .empty)
}

private func button(_ title: String, _ action: ReplyMarkupButtonAction, color: ReplyMarkupButton.Style.Color? = nil, isLink: Bool = false) -> InstantPageButton {
    return InstantPageButton(text: .plain(title), action: action, color: color, isLink: isLink)
}

private let copyTextButton = button("Copy text", .copyText(payload: "Copied from the fixture"), color: .danger)

private func workingButtons(profilePeerId: PeerId) -> [InstantPageButton] {
    return [
        button("Open URL", .url("https://telegram.org"), color: .primary),
        button("My profile", .openUserProfile(peerId: profilePeerId), color: .success),
        copyTextButton,
    ]
}

private let messageBoundButtons: [InstantPageButton] = [
    button("Callback", .callback(requiresPassword: false, data: MemoryBuffer())),
    button("Switch inline", .switchInline(samePeer: true, query: "fixture", peerTypes: [])),
    button("URL auth", .urlAuth(url: "https://telegram.org", buttonId: 0)),
    button("Web app", .openWebApp),
    button("Web view", .openWebView(url: "https://telegram.org", simple: false)),
]

private let disabledButton = button("Disabled", .disabled)

private func tableRows() -> [InstantPageTableRow] {
    func row(_ texts: [String], header: Bool = false) -> InstantPageTableRow {
        return InstantPageTableRow(cells: texts.map {
            InstantPageTableCell(text: .plain($0), header: header, alignment: .left, verticalAlignment: .top, colspan: 1, rowspan: 1)
        })
    }
    func cell(_ text: RichText, _ alignment: TableHorizontalAlignment = .left, _ verticalAlignment: TableVerticalAlignment = .top) -> InstantPageTableCell {
        return InstantPageTableCell(text: text, header: false, alignment: alignment, verticalAlignment: verticalAlignment, colspan: 1, rowspan: 1)
    }
    return [
        row(["Block", "Level", "Note"], header: true),
        row(["heading", "1-6", "All six levels"]),
        row(["table", "n/a", "Same rows in both tables, so insets compare"]),
        // Clicks here go through the table's own hit testing and stored insets.
        InstantPageTableRow(cells: [
            cell(.url(text: .plain("Link"), url: "https://telegram.org", webpageId: nil)),
            cell(.textTonAddress(text: .plain(validTonAddress))),
            cell(.textButton(button("Copy from cell", .copyText(payload: "Copied from a table cell")))),
        ]),
        // Right-aligned hit testing: a mirrored x would swap the two buttons.
        InstantPageTableRow(cells: [
            cell(.plain("Right-aligned clicks")),
            cell(.concat([.url(text: .plain("Link"), url: "https://telegram.org", webpageId: nil), .plain(" then text")]), .right),
            cell(.concat([.textButton(button("First", .copyText(payload: "First"))), .plain("  "), .textButton(button("Second", .copyText(payload: "Second")))]), .right),
        ]),
        InstantPageTableRow(cells: [
            cell(.plain("A taller cell, so that its neighbours have room to show their vertical alignment when the text wraps")),
            cell(.plain("Centre, middle"), .center, .middle),
            cell(.plain("Right, bottom"), .right, .bottom),
        ]),
        // An inline image is an additional item, the height trim's only user.
        InstantPageTableRow(cells: [
            cell(.plain("Inline image")),
            cell(.image(id: inlineImageId, dimensions: PixelDimensions(width: 40, height: 40))),
            cell(.concat([.plain("With text "), .image(id: inlineImageId, dimensions: PixelDimensions(width: 40, height: 40))])),
        ]),
    ]
}

private func buttonBlocks(profilePeerId: PeerId) -> [InstantPageBlock] {
    let working = workingButtons(profilePeerId: profilePeerId)
    let inlineButtons: [RichText] = (working + messageBoundButtons + [disabledButton, button("Link style", .url("https://telegram.org"), isLink: true)]).flatMap { button -> [RichText] in
        return [.textButton(button), .plain("  ")]
    }
    let linkInside = InstantPageButton(text: .concat([.plain("Link "), .url(text: .plain("inside"), url: "https://telegram.org", webpageId: nil)]), action: .copyText(payload: "Label with a link"), color: .primary, isLink: false)
    let disabledWithLinkInside = InstantPageButton(text: .url(text: .plain("Disabled, link inside"), url: "https://telegram.org", webpageId: nil), action: .disabled, color: nil, isLink: false)
    let disabledWithTonInside = InstantPageButton(text: .textTonAddress(text: .plain(validTonAddress)), action: .disabled, color: nil, isLink: false)
    return [
        .header(.plain("Inline buttons")),
        .paragraph(.concat([.plain("Inside text: ")] + inlineButtons)),
        .header(.plain("Button rows")),
        .paragraph(.plain("Working actions, in each alignment:")),
        .buttonRow(alignment: .left, buttons: working),
        .buttonRow(alignment: .center, buttons: working),
        .buttonRow(alignment: .right, buttons: working),
        .buttonRow(alignment: .justify, buttons: working),
        .paragraph(.plain("Message-bound actions show a toast:")),
        .buttonRow(alignment: .left, buttons: messageBoundButtons),
        .paragraph(.plain("A disabled button does nothing:")),
        .buttonRow(alignment: .left, buttons: [disabledButton]),
        .paragraph(.plain("The schema's maximum of eight, to check wrapping when narrow:")),
        .buttonRow(alignment: .justify, buttons: (1 ... 8).map { button("Button \($0)", .copyText(payload: "Button \($0)")) }),
        .paragraph(.plain("Link style, coloured disabled, a t.me link and a label containing a link:")),
        .buttonRow(alignment: .left, buttons: [
            button("Link style", .url("https://telegram.org"), isLink: true),
            button("Disabled", .disabled, color: .danger),
            button("t.me link", .url("https://t.me/telegram"), color: .primary),
            linkInside,
        ]),
        .paragraph(.plain("Labels too long for the row, tight padding then truncation:")),
        .buttonRow(alignment: .left, buttons: [button(String(repeating: "A long label ", count: 12), .copyText(payload: "Long label"))]),
        .buttonRow(alignment: .justify, buttons: (1 ... 3).map { button(String(repeating: "Long label \($0) ", count: 4), .copyText(payload: "Long label \($0)")) }),
        .paragraph(.plain("An empty row follows; nothing should render for it:")),
        .buttonRow(alignment: .left, buttons: []),
        .header(.plain("Nested rich text")),
        // Neither the link nor the address may fire inside a disabled button.
        .paragraph(.concat([.plain("Disabled over nested actions: "), .textButton(disabledWithLinkInside), .plain("  "), .textButton(disabledWithTonInside)])),
        .paragraph(.concat([.plain("Disabled inside a link, should not open: "), .url(text: .textButton(disabledButton), url: "https://telegram.org", webpageId: nil)])),
        // The action wins over the surrounding link.
        .paragraph(.concat([.plain("Address inside a link, copies: "), .url(text: .textTonAddress(text: .plain(validTonAddress)), url: "https://telegram.org", webpageId: nil)])),
    ]
}

// Tiles start every 256pt and exist only around text, so text sits between
// short runs of rows: wherever the page starts, some rows cross a tile's edge.
private func tileBoundaryBlocks() -> [InstantPageBlock] {
    var blocks: [InstantPageBlock] = [
        .header(.plain("Clicks across text tiles")),
        .paragraph(.plain("Every pill and document below must respond along its whole height.")),
    ]
    for group in 1 ... 6 {
        blocks.append(.paragraph(.plain("Button rows, group \(group):")))
        blocks += (1 ... 3).map { row in
            .buttonRow(alignment: .justify, buttons: [button("Group \(group), row \(row)", .copyText(payload: "Group \(group), row \(row)"))])
        }
    }
    blocks += (1 ... 8).map { document in
        .document(id: storedDocumentId, caption: caption("Stored document \(document)."))
    }
    return blocks
}

private func instantPageDebugFixture(profilePeerId: PeerId, rtl: Bool, storedDocument: TelegramMediaFile, unfetchableDocument: TelegramMediaFile, riskyDocument: TelegramMediaFile, namelessDocument: TelegramMediaFile, inlineImage: TelegramMediaFile) -> TelegramMediaWebpage {
    let title = rtl ? "Instant Page fixture (RTL)" : "Instant Page fixture"
    let url = rtl ? rtlFixtureUrl : ltrFixtureUrl
    var blocks: [InstantPageBlock] = [
        .title(.plain(title)),
        .subtitle(.plain("Renders local blocks; no server content")),
        .paragraph(.plain("هذه فقرة باللغة العربية لفحص اتجاه النص من اليمين إلى اليسار.")),
    ]
    // 0 and 7 are outside the schema, to check clamping.
    blocks += (0 ... 7).map { level in
        .heading(text: .plain("Heading level \(level)"), level: Int32(level))
    }
    blocks += [
        .header(.plain("Thinking")),
        .thinking(.plain("A thinking block, shown as secondary text. It should wrap like a paragraph when the text is long enough to reach the end of the line.")),
        .header(.plain("Formula")),
        .formula(latex: "E = mc^2"),
        .paragraph(.concat([.plain("Inline formula, for comparison: "), .formula(latex: "a^2 + b^2 = c^2")])),
        .header(.plain("Tables")),
        .table(title: .plain("Regular"), rows: tableRows(), bordered: true, striped: true, compact: false),
        .table(title: .plain("Compact"), rows: tableRows(), bordered: true, striped: true, compact: true),
        .header(.plain("TON addresses")),
        .paragraph(.concat([.plain("Valid, copies on click: "), .textTonAddress(text: .plain(validTonAddress))])),
        .paragraph(.concat([.plain("Invalid, stays plain: "), .textTonAddress(text: .plain(invalidTonAddress))])),
    ]
    blocks += buttonBlocks(profilePeerId: profilePeerId)
    blocks += tileBoundaryBlocks()
    blocks += [
        .header(.plain("Documents")),
        .document(id: storedDocumentId, caption: caption("Stored locally: opens in Quick Look, without a download.")),
        .document(id: unfetchableDocumentId, caption: caption("Not stored and has no server copy: shows the remote state and never finishes downloading.")),
        .document(id: missingDocumentId, caption: caption("Media missing from the page: only this caption renders.")),
        .document(id: riskyDocumentId, caption: caption("Stored, upper-case risky extension: warns before opening.")),
        .document(id: namelessDocumentId, caption: caption("Stored, no name and an HTML MIME type: shows the fallback name and warns before opening.")),
        // Details items have their own hit-test path.
        .details(title: .plain("Details, expanded"), blocks: [
            .paragraph(.concat([.plain("Address: "), .textTonAddress(text: .plain(validTonAddress)), .plain("  Button: "), .textButton(copyTextButton)])),
            .buttonRow(alignment: .center, buttons: workingButtons(profilePeerId: profilePeerId)),
            .document(id: storedDocumentId, caption: caption("Stored document inside details.")),
        ], expanded: true),
        .details(title: .plain("Details, collapsed"), blocks: [
            .buttonRow(alignment: .justify, buttons: messageBoundButtons),
        ], expanded: false),
    ]

    let page = InstantPage(blocks: blocks, media: [
        storedDocumentId: storedDocument,
        unfetchableDocumentId: unfetchableDocument,
        riskyDocumentId: riskyDocument,
        namelessDocumentId: namelessDocument,
        inlineImageId: inlineImage,
    ], isComplete: true, rtl: rtl, url: url, views: nil)

    return TelegramMediaWebpage(webpageId: rtl ? rtlWebpageId : ltrWebpageId, content: .Loaded(TelegramMediaWebpageLoadedContent(url: url, displayUrl: url, hash: 0, type: "article", websiteName: title, title: title, text: nil, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: nil, attributes: [], instantPage: page)))
}

private func localDocument(id: MediaId, fileName: String?, mimeType: String = "text/plain", size: Int64?, attributes: [TelegramMediaFileAttribute] = []) -> TelegramMediaFile {
    return TelegramMediaFile(fileId: id, partialReference: nil, resource: LocalFileMediaResource(fileId: id.id, size: size), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: size, attributes: fileName.map { [.FileName(fileName: $0)] + attributes } ?? attributes, alternativeRepresentations: [])
}

private var opensRtlFixtureNext = false

/// Opens the fixture page, alternating between LTR and RTL on each call.
func openInstantPageDebugFixture(context: AccountContext) {
    let rtl = opensRtlFixtureNext
    opensRtlFixtureNext.toggle()

    let storedData = Data("Stored by the Instant Page fixture.\n".utf8)
    let size = Int64(storedData.count)
    let storedDocument = localDocument(id: storedDocumentId, fileName: "fixture.txt", size: size)
    let riskyDocument = localDocument(id: riskyDocumentId, fileName: "FIXTURE.HTML", size: size)
    let namelessDocument = localDocument(id: namelessDocumentId, fileName: nil, mimeType: "text/html", size: size)
    for document in [storedDocument, riskyDocument, namelessDocument] {
        context.account.postbox.mediaBox.storeResourceData(document.resource.id, data: storedData, synchronous: true)
    }
    let unfetchableDocument = localDocument(id: unfetchableDocumentId, fileName: "a very long file name that should be cut in the middle so the extension stays visible on a narrow page.txt", size: nil)
    let inlineImage = localDocument(id: inlineImageId, fileName: nil, mimeType: "image/png", size: nil, attributes: [.ImageSize(size: PixelDimensions(width: 40, height: 40))])

    let webPage = instantPageDebugFixture(profilePeerId: context.peerId, rtl: rtl, storedDocument: storedDocument, unfetchableDocument: unfetchableDocument, riskyDocument: riskyDocument, namelessDocument: namelessDocument, inlineImage: inlineImage)
    BrowserStateContext.get(context).open(tab: .instantView(url: rtl ? rtlFixtureUrl : ltrFixtureUrl, webPage: webPage, anchor: nil))
}

#endif
