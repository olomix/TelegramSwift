//
//  CoreCompat.swift
//  Telegram
//
//  Adapts the Mac app to API changes in the Telegram-iOS core.
//

import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import ColorPalette

extension EngineMessageReplyInnerSubject {
    var todoItemId: Int32? {
        if case let .todoItem(id) = self {
            return id
        }
        return nil
    }
}

extension ReplyMessageAttribute {
    var todoItemId: Int32? {
        return self.innerSubject?.todoItemId
    }
}

// Core APIs now return EnginePeer where they used to return Peer.
extension EnginePeer {
    var displayTitle: String {
        return self._asPeer().displayTitle
    }
    var rawDisplayTitle: String {
        return self._asPeer().rawDisplayTitle
    }
    var isUser: Bool {
        return self._asPeer().isUser
    }
    var isBot: Bool {
        return self._asPeer().isBot
    }
    var isGroup: Bool {
        return self._asPeer().isGroup
    }
    var isSupergroup: Bool {
        return self._asPeer().isSupergroup
    }
    var isChannel: Bool {
        return self._asPeer().isChannel
    }
    var username: String? {
        return self._asPeer().username
    }
    var isForum: Bool {
        return self._asPeer().isForum
    }
}

// Chat themes are now `ChatTheme`; the Mac UI only supports emoticon themes.
extension ChatTheme {
    var emoticonValue: String? {
        if case let .emoticon(emoticon) = self {
            return emoticon
        }
        return nil
    }
}

extension CachedUserData {
    var themeEmoticon: String? {
        return self.chatTheme?.emoticonValue
    }
}

extension CachedGroupData {
    var themeEmoticon: String? {
        return self.chatTheme?.emoticonValue
    }
}

extension CachedChannelData {
    var themeEmoticon: String? {
        return self.chatTheme?.emoticonValue
    }
}

extension PeerColor {
    var presetValue: PeerNameColor? {
        if case let .preset(color) = self {
            return color
        }
        return nil
    }
}

// Removed from TelegramCore; restored for the Mac app.
func resetAuthorizationState(account: UnauthorizedAccount) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Void in
        if let state = transaction.getState() as? UnauthorizedAccountState {
            transaction.setState(UnauthorizedAccountState(isTestingEnvironment: state.isTestingEnvironment, masterDatacenterId: state.masterDatacenterId, contents: .empty))
        }
    }
}

func peerViewMonoforumMainPeer(_ view: PeerView) -> Peer? {
    if let channel = peerViewMainPeer(view) as? TelegramChannel, channel.flags.contains(.isMonoforum), let linkedMonoforumId = channel.linkedMonoforumId {
        return view.peers[linkedMonoforumId]
    }
    return nil
}

extension JoinLinkResult {
    // The Mac UI has no join web view yet; such results are treated as not joined.
    var joinedPeer: EnginePeer? {
        if case let .joined(peer) = self {
            return peer
        }
        return nil
    }
}

struct ChatListFilteringConfiguration: Equatable {
    let isEnabled: Bool

    init(appConfiguration: AppConfiguration) {
        if let data = appConfiguration.data, let value = data["dialog_filters_enabled"] as? Bool {
            self.isEnabled = value
        } else {
            self.isEnabled = false
        }
    }
}

// Collectible name colors aren't rendered on macOS; they fall back to blue.
extension PeerColor {
    static var blue: PeerColor {
        return .preset(.blue)
    }
}

extension PeerNameColors {
    func get(_ color: PeerColor, dark: Bool = false) -> Colors {
        return self.get(color.presetValue ?? .blue, dark: dark)
    }
}

extension TelegramMediaPollKind {
    var isQuiz: Bool {
        if case .quiz = self {
            return true
        }
        return false
    }
}
