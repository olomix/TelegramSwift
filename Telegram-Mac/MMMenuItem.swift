//
//  MMMenuItem.swift
//  Telegram
//
//  Created by keepcoder on 28/05/2017.
//  Copyright © 2017 Telegram. All rights reserved.
//

import Cocoa
import Localization

// App menu, About, Hide and Quit. Language packs downloaded from Telegram's
// servers override the bundled strings and name the app "Telegram".
private let appNameMenuIdentifiers: Set<String> = [
    "1Xt-HY-uBw", "uQy-DD-JDr", "5kV-Vb-QxS", "Cag-YX-WT6", "4sb-4s-VLi",
]

private func localizedMenuTitle(_ identifier: String) -> String {
    let title = _NSLocalizedString("\(identifier).title")
    if appNameMenuIdentifiers.contains(identifier) {
        return title.replacingOccurrences(of: "Telegram", with: appName)
    }
    return title
}

class MMMenuItem: NSMenuItem {
    override var title: String {
        get {
            if let identifier = identifier?.rawValue {
                return localizedMenuTitle(identifier)
            }
            return super.title
        }
        set {
            super.title = newValue
        }
    }
}


class MMMenu : NSMenu {
    override var title: String {
       
        get {
            if let identifier = identifier?.rawValue {
                return localizedMenuTitle(identifier)
            }
            return super.title
        }
        set {
            super.title = newValue
        }
        
    }
}
