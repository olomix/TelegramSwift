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

// Fixed IDs so reopening reuses the browser tab and the stored file.
private let fixtureWebpageId = MediaId(namespace: Namespaces.Media.LocalWebpage, id: 0x7E1E_F1C7)
private let storedDocumentId = MediaId(namespace: Namespaces.Media.LocalFile, id: 0x7E1E_F1C8)
private let unfetchableDocumentId = MediaId(namespace: Namespaces.Media.LocalFile, id: 0x7E1E_F1C9)
private let missingDocumentId = MediaId(namespace: Namespaces.Media.LocalFile, id: 0x7E1E_F1CA)

// .invalid never resolves: the page controller asks the server to refresh its URL.
private let fixtureUrl = "https://telex.invalid/instant-page-fixture"
// Passes isValidTonAddress but is no real wallet; a click copies it.
private let validTonAddress = "EQTelexInstantPageFixture_NotARealAddress-000000"
private let invalidTonAddress = "EQTooShortToBeAnAddress"

private func caption(_ text: String) -> InstantPageCaption {
    return InstantPageCaption(text: .plain(text), credit: .empty)
}

private func button(_ title: String, _ action: ReplyMarkupButtonAction, color: ReplyMarkupButton.Style.Color? = nil, isLink: Bool = false) -> InstantPageButton {
    return InstantPageButton(text: .plain(title), action: action, color: color, isLink: isLink)
}

private func workingButtons(profilePeerId: PeerId) -> [InstantPageButton] {
    return [
        button("Open URL", .url("https://telegram.org"), color: .primary),
        button("My profile", .openUserProfile(peerId: profilePeerId), color: .success),
        button("Copy text", .copyText(payload: "Copied from the fixture"), color: .danger),
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
    return [
        row(["Block", "Level", "Note"], header: true),
        row(["heading", "1-6", "All six levels"]),
        row(["table", "n/a", "Same rows in both tables, so insets compare"]),
    ]
}

private func buttonBlocks(profilePeerId: PeerId) -> [InstantPageBlock] {
    let working = workingButtons(profilePeerId: profilePeerId)
    let inlineButtons: [RichText] = (working + messageBoundButtons + [disabledButton, button("Link style", .url("https://telegram.org"), isLink: true)]).flatMap { button -> [RichText] in
        return [.textButton(button), .plain("  ")]
    }
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
    ]
}

private func instantPageDebugFixture(profilePeerId: PeerId, storedDocument: TelegramMediaFile, unfetchableDocument: TelegramMediaFile) -> TelegramMediaWebpage {
    var blocks: [InstantPageBlock] = [
        .title(.plain("Instant Page fixture")),
        .subtitle(.plain("Renders local blocks; no server content")),
    ]
    blocks += (1 ... 6).map { level in
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
    blocks += [
        .header(.plain("Documents")),
        .document(id: storedDocumentId, caption: caption("Stored locally: opens in Quick Look, without a download.")),
        .document(id: unfetchableDocumentId, caption: caption("Not stored and has no server copy: shows the remote state and never finishes downloading.")),
        .document(id: missingDocumentId, caption: caption("Media missing from the page: only this caption renders.")),
    ]

    let page = InstantPage(blocks: blocks, media: [
        storedDocumentId: storedDocument,
        unfetchableDocumentId: unfetchableDocument,
    ], isComplete: true, rtl: false, url: fixtureUrl, views: nil)

    return TelegramMediaWebpage(webpageId: fixtureWebpageId, content: .Loaded(TelegramMediaWebpageLoadedContent(url: fixtureUrl, displayUrl: fixtureUrl, hash: 0, type: "article", websiteName: "Instant Page fixture", title: "Instant Page fixture", text: nil, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: nil, attributes: [], instantPage: page)))
}

private func localDocument(id: MediaId, fileName: String, size: Int64?) -> TelegramMediaFile {
    return TelegramMediaFile(fileId: id, partialReference: nil, resource: LocalFileMediaResource(fileId: id.id, size: size), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "text/plain", size: size, attributes: [.FileName(fileName: fileName)], alternativeRepresentations: [])
}

func openInstantPageDebugFixture(context: AccountContext) {
    let storedData = Data("Stored by the Instant Page fixture.\n".utf8)
    let storedDocument = localDocument(id: storedDocumentId, fileName: "fixture.txt", size: Int64(storedData.count))
    context.account.postbox.mediaBox.storeResourceData(storedDocument.resource.id, data: storedData, synchronous: true)
    let unfetchableDocument = localDocument(id: unfetchableDocumentId, fileName: "a very long file name that should be cut in the middle so the extension stays visible on a narrow page.txt", size: nil)

    let webPage = instantPageDebugFixture(profilePeerId: context.peerId, storedDocument: storedDocument, unfetchableDocument: unfetchableDocument)
    BrowserStateContext.get(context).open(tab: .instantView(url: fixtureUrl, webPage: webPage, anchor: nil))
}

#endif
