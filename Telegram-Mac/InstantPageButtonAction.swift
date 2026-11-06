//
//  InstantPageButtonAction.swift
//  Telegram
//

import Cocoa
import TGUIKit
import Postbox
import TelegramCore

// Telex-only: the server language pack has no such string.
private let pageButtonUnavailableText = "This button isn't available here."

/// Runs a page button's action. A page has no message behind it, so actions
/// that need one (callbacks, web apps, inline switches) only show a toast.
func performInstantPageButtonAction(_ button: InstantPageButton, context: AccountContext, window: Window, openInfo: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) {
    switch button.action {
    case let .url(url):
        // The label hides the destination, so confirm as bot buttons do.
        let link = inApp(for: url.nsstring, context: context, openInfo: openInfo, applyProxy: { proxy in
            applyExternalProxy(proxy, accountManager: context.sharedContext.accountManager)
        }, confirm: true)
        execute(inapp: link, window: window)
    case let .openUserProfile(peerId):
        openInfo(peerId, false, nil, nil)
    case let .copyText(payload):
        copyToClipboard(payload)
        showModalText(for: window, text: strings().shareLinkCopied)
    case .disabled:
        break
    default:
        showModalText(for: window, text: pageButtonUnavailableText)
    }
}
