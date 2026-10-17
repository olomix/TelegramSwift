//
//  ColdStartPasslockController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 03.11.2020.
//  Copyright © 2020 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import SwiftSignalKit
import MacPasscode


class ColdStartPasslockController: ModalViewController {
    private let valueDisposable = MetaDisposable()
    private let logoutDisposable = MetaDisposable()
    private let touchIdDisposable = MetaDisposable()

    private let logoutImpl:() -> Signal<Never, NoError>
    private let checkNextValue: (String, @escaping (PasscodeCheckFailure?) -> Void) -> Void
    private let touchIdUnlock: (() -> Signal<Never, NoError>)?
    private var touchIdCalled = false
    /// `checkNextValue` reports nil once the code opened local data.
    /// `touchIdUnlock` opens it through Touch ID; nil hides Touch ID. A failed
    /// or cancelled prompt leaves the code field as the fallback.
    init(checkNextValue: @escaping (String, @escaping (PasscodeCheckFailure?) -> Void) -> Void, touchIdUnlock: (() -> Signal<Never, NoError>)? = nil, logoutImpl:@escaping()->Signal<Never, NoError>) {
        self.checkNextValue = checkNextValue
        self.touchIdUnlock = touchIdUnlock
        self.logoutImpl = logoutImpl
        super.init(frame: NSMakeRect(0, 0, 350, 350))
        self.bar = .init(height: 0)
    }
    
    override var isVisualEffectBackground: Bool {
        return false
    }
    
    override var isFullScreen: Bool {
        return true
    }
    
    override var background: NSColor {
        return self.containerBackground
    }
    
    private var genericView:PasscodeLockView {
        return self.view as! PasscodeLockView
    }
    
   
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        genericView.logoutImpl = { [weak self] in
            guard let window = self?.window else { return }
            
            verifyAlert_button(for: window, information: strings().accountConfirmLogoutText, successHandler: { [weak self] _ in
                guard let `self` = self else { return }
                
                _ = showModalProgress(signal: self.logoutImpl(), for: window).start(completed: { [weak self] in
                    delay(0.2, closure: { [weak self] in
                        self?.close()
                    })
                })
            })
        }
        
        // Also true while a check runs: deriving the key takes a moment.
        var locked = false
        
        valueDisposable.set((genericView.value.get() |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let `self` = self, !locked else {
                return
            }
            locked = true
            self.checkNextValue(value, { [weak self] failure in
                guard let failure else {
                    return
                }
                locked = false
                self?.genericView.show(failure)
            })
        }))
        
        genericView.useTouchIdImpl = { [weak self] in
            self?.callTouchId()
        }

        genericView.update(hasTouchId: touchIdUnlock != nil)
        readyOnce()
        
        
    }
    
    // The launch window is usually key already when the lock appears.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if window?.isKeyWindow == true {
            callTouchIdOnce()
        }
    }

    override func windowDidBecomeKey() {
        super.windowDidBecomeKey()
        callTouchIdOnce()
    }

    private func callTouchIdOnce() {
        if NSApp.isActive, touchIdUnlock != nil, !touchIdCalled {
            touchIdCalled = true
            callTouchId()
        }
    }

    private func callTouchId() {
        if let touchIdUnlock {
            touchIdDisposable.set(touchIdUnlock().start())
        }
    }

    override var closable: Bool {
        return false
    }
    
    
    override func escapeKeyAction() -> KeyHandlerResult {
        return .invoked
    }
    
    override func firstResponder() -> NSResponder? {
        if !(window?.firstResponder is NSText) {
            return genericView.input
        }
        let editor = self.window?.fieldEditor(true, for: genericView.input)
        if window?.firstResponder != editor {
            return genericView.input
        }
        return editor
        
    }
    
    override var containerBackground: NSColor {
        return theme.colors.background.withAlphaComponent(1.0)
    }
    override var handleEvents: Bool {
        return true
    }
    
    override var cornerRadius: CGFloat {
        return 0
    }
    
    override var handleAllEvents: Bool {
        return true
    }
    
    
    override var responderPriority: HandlerPriority {
        return .supreme
    }
    
    deinit {
        logoutDisposable.dispose()
        valueDisposable.dispose()
        touchIdDisposable.dispose()
        self.window?.removeAllHandlers(for: self)
    }
    
    override func viewClass() -> AnyClass {
        return PasscodeLockView.self
    }
    
}

