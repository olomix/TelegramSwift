//
//  InstantPageView.swift
//  Telegram
//
//  Created by keepcoder on 10/08/2017.
//  Copyright © 2017 Telegram. All rights reserved.
//

import Cocoa


protocol InstantPageView {
    func updateIsVisible(_ isVisible: Bool)
}

/// A view that gets its clicks from normal hit testing, not the window handler.
protocol InstantPageClickableView: InstantPageView {}

// Text tiles are transparent but take clicks meant for a row they cross, so
// rows go on top. separatesTiles would clip the text around them instead.
func sortInstantPageSubviews(of parent: NSView) {
    let sorted = parent.subviews.sorted(by: { $0.frame.minY < $1.frame.minY })
    parent.subviews = sorted.filter { !($0 is InstantPageClickableView) } + sorted.filter { $0 is InstantPageClickableView }
}
