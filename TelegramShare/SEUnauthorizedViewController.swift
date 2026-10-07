//
//  SEUnauthorizedViewController.swift
//  Telegram
//
//  Created by keepcoder on 29/03/2017.
//  Copyright © 2017 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import Localization

class SEUnauthorizedView : View {
    fileprivate let imageView:ImageView = ImageView()
    fileprivate let cancel:TextButton = TextButton()
    fileprivate let textView:TextView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        imageView.image = #imageLiteral(resourceName: "Icon_TelegramLogin").precomposed()
        imageView.sizeToFit()
        self.backgroundColor = theme.colors.background
        cancel.set(font: .medium(.title), for: .Normal)
        cancel.set(color: theme.colors.accent, for: .Normal)
        cancel.set(text: L10n.shareExtensionUnauthorizedOK, for: .Normal)
        
        textView.backgroundColor = theme.colors.background
        setDescription(L10n.shareExtensionUnauthorizedDescription)
        
        addSubview(cancel)
        addSubview(textView)
        addSubview(imageView)
    }
    
    
    func setDescription(_ text: String) {
        textView.update(TextViewLayout(.initialize(string: text, color: theme.colors.text, font: .normal(.text)), alignment: .center))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        imageView.centerX(y: 30)
        textView.textLayout?.measure(width: frame.width - 60)
        textView.update(textView.textLayout)
        textView.center()
        cancel.centerX(y: textView.frame.maxY + 20)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class SEUnauthorizedViewController: GenericViewController<SEUnauthorizedView> {
    private let cancelImpl:()->Void
    private let descriptionText: String
    init(description: String = L10n.shareExtensionUnauthorizedDescription, cancelImpl:@escaping()->Void) {
        self.descriptionText = description
        self.cancelImpl = cancelImpl
        super.init()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        genericView.setDescription(descriptionText)
        genericView.cancel.set(handler: { [weak self] _ in
            self?.cancelImpl()
        }, for: .Click)
    }
    
}
