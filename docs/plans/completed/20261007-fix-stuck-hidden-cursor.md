# Fix Mouse Pointer Stuck Hidden After Video Playback

## Overview
- Sometimes the mouse pointer is invisible while Telegram is the active app.
  It reappears in other apps and disappears again when Telegram is
  activated.
- Cause: `NSCursor.hide()`/`unhide()` is a per-app counter that AppKit
  applies only while the app is frontmost. `SVideoController` hides the
  cursor on idle without pairing every hide with an unhide, so the counter
  can stay above zero after the video viewer is gone.
- Fix: the controller owns at most one hide, hides only while it is
  actually the thing the user looks at, and always releases its hide when
  it stops being visible or is deallocated.

## Context (from discovery)
- `Telegram-Mac/SVideoController.swift` — the only code in the repo that
  hides the cursor:
  - `updateIdleTimer()` (:164-174): `unhide()` now, `hide()` after 1s idle.
  - `updateControlVisibility(_:)` (:177-203): extra `hide()` on mouse
    down/up in fullscreen; balanced by the `unhide()` in the
    `updateIdleTimer()` call that follows (:258/:260, :269/:272).
  - `setHandlersOn(window:)` (:207-293): mouse handlers; `mouseExited`
    (:235) re-arms the idle hide after the pointer leaves the viewer.
  - `viewDidDisappear` (:333-340): one `unhide()`, removes handlers.
  - `togglePictureInPicture()` (:630-644) and `toggleFullScreen()`
    (:662-710): move the view to another window and re-run
    `setHandlersOn`.
  - playback-completed closures (:589-603): call `updateIdleTimer()`
    asynchronously with no check that the view is still shown.
  - `deinit` (:719-733): disposes the timer but never unhides.
- `Telegram-Mac/GalleryViewer.swift` `close(_:)` (:1653-1687): the
  non-animated branch (default, `animated = false`) only `orderOut`s the
  window, so `viewDidDisappear` never runs. Callers include
  `ApplicationContext.swift:936`, `GalleryViewer.swift:1499/1506/1513`,
  and `MGalleryVideoItem.swift:55` (PiP entry).
- `packages/TGUIKit/Sources/ViewController.swift:906-907`: key-window
  observers are bound to the window present at `viewDidAppear`; they do
  not follow fullscreen/PiP reparenting.
- `packages/FoundationUtils`: dependency-free package already linked into
  the app; it gets the new helper and the project's first test target.
- No other cursor hiding exists (stories and calls only fade controls,
  e.g. `GroupCallView.swift:397-430`).

## Development Approach
- **testing approach**: Regular (code first, then tests)
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes
  in that task
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during
  implementation**
- the app has no test target; logic that can be tested lives in
  `FoundationUtils` and is tested with `swift test`. AppKit wiring in
  `SVideoController` is verified by an app build plus the manual checks in
  Post-Completion.

## Testing Strategy
- **unit tests**: `cd packages/FoundationUtils && swift test`
- **build check**: `xcodebuild -workspace Telegram-Mac.xcworkspace -scheme
  Telegram -configuration Debug -destination 'platform=macOS,arch=arm64'
  -derivedDataPath ~/build/TelegramSwift build`
- **e2e**: none in the project; manual scenarios in Post-Completion.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- keep plan in sync with actual work done

## Solution Overview
- New `CursorHider` value-owning class in `FoundationUtils`:
  - takes `hide`/`unhide` closures (production: `NSCursor.hide/unhide`;
    tests: counters), so it has no AppKit dependency;
  - `hide()` and `show()` are idempotent: the controller contributes at
    most 1 to the system counter;
  - `deinit` calls `show()` as a last-resort release.
- New pure function `shouldHideCursorOnIdle(_ conditions:)` taking a
  small struct of booleans (window visible, window key, app active,
  pointer inside the view, pointer needed elsewhere). Keeps the decision
  testable; the player folds menu, controls, context menu and PiP into
  `isPointerNeeded`.
- New `CursorIdleController` in `FoundationUtils`: owns the
  `CursorHider`, the appearance flag and the pending idle callback, with
  an injected scheduler. It holds the whole idle-hide state machine, so
  it is unit tested; `SVideoController` keeps only AppKit wiring
  (notifications, windows, building the conditions).
- Timer policy: scheduling is gated only on appearance; the full
  eligibility check runs when the timer fires and gates only the cursor
  hide. The callback still updates `hideControls` as today, so controls
  keep fading in PiP and when the pointer is outside the player.
- Two release operations:
  - `showCursor()` — cancel pending idle callback + show cursor. Used on
    focus loss; appearance is kept so focus regain can rearm.
  - `endAppearance()` — clear appearance + `showCursor()`. Used by
    `viewDidDisappear`, `GalleryViewer`'s non-animated close and PiP
    panel close, so queued playback completions cannot rearm.
- Focus model is unchanged from master: in video fullscreen the gallery
  window stays key (it owns the Space/F/Esc/arrow handlers), the
  fullscreen window only shows the video. The idle check takes window
  visibility and pointer hit-testing from the window that hosts the
  video, and key focus from the focus owner (gallery window while
  fullscreen, the hosting window otherwise).
- Rearm paths: focus-owner become-key and app become-active call
  `updateIdleTimer()`; fullscreen entry rearms only after the view is in
  the fullscreen window.
- `deinit` relies on `CursorIdleController`/`CursorHider` release.

## Technical Details
- `CursorHider`
  - `init(hide: @escaping () -> Void, unhide: @escaping () -> Void)`
  - `private(set) var isHidden: Bool`
  - `func hide()` — calls `hide` only when `!isHidden`
  - `func show()` — calls `unhide` only when `isHidden`
  - `deinit { show() }`
- `CursorIdleConditions` struct + `shouldHideCursorOnIdle(_:) -> Bool`
  (`CursorIdleConditions.swift`): true only when window visible, window
  key, app active, mouse inside and pointer not needed elsewhere.
- `CursorIdleController`
  - `init(hide:unhide:schedule:)`; `schedule` runs a closure once after
    the idle delay and returns a cancel closure
  - `appear()`, `endAppearance()`, `showCursor()`
  - `rearm(onIdle:)` — `showCursor()`, then schedule `onIdle` only while
    appeared
  - `hideIfIdle(_ conditions:)` — hide only while appeared and
    `shouldHideCursorOnIdle` is true
  - `deinit` cancels the pending callback; the hider releases the hide
- `SVideoController`
  - `cursorIdle = CursorIdleController(hide: NSCursor.hide, unhide:
    NSCursor.unhide, schedule: scheduleAfterIdleDelay)`; `idleDelay`
    is 1s via a SwiftSignalKit delay
  - `viewDidAppear` → `cursorIdle.appear()`; `viewDidDisappear` →
    `endAppearance()`
  - `updateIdleTimer()` → `cursorIdle.rearm`; the callback sets
    `hideControls` from `isPointerOnControls` (menu, controls, context
    menu) exactly as before, then `hideCursorIfIdle(isPointerOnControls:)`
  - `focusWindow`: the gallery window (`fullScreenRestoreState.view
    .window`) while fullscreen, else `view.window` (the PiP panel in
    PiP, not the dummy mouse-dispatch `Window`)
  - `hideCursorIfIdle(isPointerOnControls:)` builds
    `CursorIdleConditions` with `isWindowVisible` from
    `genericView.window`, `isWindowKey` from `focusWindow`,
    `NSApp.isActive`, `genericView.mediaPlayer._mouseInside()` and
    `isPointerNeeded = isPointerOnControls || pictureInPicture`
  - `updateControlVisibility(true)` no longer hides the cursor: on
    master its hide was undone at once by the `updateIdleTimer()` that
    follows in the mouse-down/up handlers; the idle timer does the hide
  - focus observers, bound in `setHandlersOn` to `focusWindow` and
    re-bound whenever the view moves (fullscreen/PiP); `removeAllHandlers`
    does not remove them, `observeFocus` replaces them:
    - `NSWindow.didResignKeyNotification`,
      `NSApplication.didResignActiveNotification` → `cursorIdle.showCursor()`
    - `NSWindow.didBecomeKeyNotification`,
      `NSApplication.didBecomeActiveNotification` → `updateIdleTimer()`
  - `toggleFullScreen()`: keeps master's `becomeKey()` (the fullscreen
    window does not take key); entry calls `setHandlersOn` after the
    view is in the fullscreen window; exit re-binds to the gallery window
  - `togglePictureInPicture()`: entering PiP closes the gallery, which
    ends appearance, so it calls `cursorIdle.appear()` before
    `setHandlersOn` on the PiP window
  - playback-completed closures call `updateIdleTimer()`; the
    appearance gate lives in `rearm`
  - `endAppearance()` — remove focus observers,
    `cursorIdle.endAppearance()`
- `GalleryViewer.close(_:)` non-animated branch: call
  `MGalleryVideoItem.exitFullscreenAndEndPlayerAppearance()` before
  `orderOut`; it leaves
  fullscreen first if needed, then ends appearance.
- `PictureInPictureControl.endAppearance()`: `closePipVideo()` calls it
  after hiding the panel. Return-to-gallery goes through
  `openGallery()`, not `closePipVideo()`, so the reopened gallery's
  `viewDidAppear` keeps the controller appeared.

## What Goes Where
- **Implementation Steps**: code, unit tests, build check, docs.
- **Post-Completion**: manual reproduction in the running app.

## Implementation Steps

### Task 1: Add CursorHider and idle-hide decision to FoundationUtils

**Files:**
- Create: `packages/FoundationUtils/Sources/FoundationUtils/CursorHider.swift`
- Modify: `packages/FoundationUtils/Package.swift`
- Create: `packages/FoundationUtils/Tests/FoundationUtilsTests/CursorHiderTests.swift`

- [x] implement `CursorHider` with idempotent `hide()`/`show()` and
      release in `deinit`
- [x] implement `CursorIdleConditions` and `shouldHideCursorOnIdle(_:)`
- [x] add `FoundationUtilsTests` test target to `Package.swift`
- [x] write tests: repeated `hide()` calls the closure once; `show()`
      after hide calls unhide once; `show()` without hide is a no-op;
      deinit releases a held hide; deinit without hide calls nothing
- [x] write tests: `shouldHideCursorOnIdle` is true for the all-good
      case and false when each single condition fails
- [x] run `swift test` in `packages/FoundationUtils` — must pass

### Task 2: Route SVideoController cursor changes through CursorHider

**Files:**
- Modify: `Telegram-Mac/SVideoController.swift`

- [x] add `cursorHider` and `isAppeared`; set `isAppeared = true` in
      `viewDidAppear`
- [x] replace every `NSCursor.hide()`/`unhide()` call with
      `cursorHider` calls
- [x] add `releaseCursor()` and `endAppearance()` (see Technical
      Details); call `endAppearance()` from `viewDidDisappear`
- [x] `updateIdleTimer()`: schedule only when `isAppeared`; in the
      callback keep the existing `hideControls` update unconditional and
      gate only `cursorHider.hide()` on `shouldHideCursorOnIdle`
- [x] guard the mouse-up/down hide in `updateControlVisibility` with the
      same conditions
- [x] gate the playback-completed `updateIdleTimer()` calls on
      `isAppeared`
- [x] extend Task 1 tests if a new condition was needed (none needed)
- [x] run `swift test` and the app build — must pass

### Task 3: Track focus and window moves for the cursor

**Files:**
- Modify: `Telegram-Mac/SVideoController.swift`

- [x] observe window resign-key and app resign-active → `releaseCursor()`
- [x] observe window become-key and app become-active →
      `updateIdleTimer()`
- [x] bind window observers to the current `view.window`; re-bind when
      the view moves to the fullscreen or PiP window and back
- [x] in `toggleFullScreen()` entry, set handlers / rearm only after the
      view is in the fullscreen window and it is key
- [x] remove observers in `endAppearance()` and `deinit`
- [x] run `swift test` and the app build — must pass

### Task 4: End appearance on non-animated gallery close

**Files:**
- Modify: `Telegram-Mac/GalleryViewer.swift`
- Modify: `Telegram-Mac/MGalleryVideoItem.swift` (if the controller is
  only reachable through the item)

- [x] in `close(_:)` non-animated branch, call `endAppearance()` on the
      selected video item's `SVideoController` before `orderOut`
- [x] PiP entry (`MGalleryVideoItem.swift:55` `closeGalleryViewer(false)`
      → `endAppearance()`): explicitly restore appearance once PiP
      attachment completes — set `isAppeared = true`, bind focus
      observers to the actual PiP hosting window, and rearm via
      `updateIdleTimer()` — so PiP controls keep fading. Check the call
      order of `endAppearance()` vs `togglePictureInPicture()` so the
      restore runs last
- [x] ➕ in PiP, bind focus observers to the hosting panel, not the
      dummy mouse-dispatch `Window` from the panel's content view
- [x] ➕ ~~keep the fullscreen window key~~ — reverted after review: it
      broke Space/F/Esc/arrows in fullscreen. The gallery window stays
      key; the idle check and focus observers use it as focus owner
- [x] add `CursorHider` test: hide → show → deinit calls unhide only once
- [x] run `swift test` and the app build — must pass

### Task 5: Verify acceptance criteria
- [x] no direct `NSCursor.hide`/`unhide` calls remain outside
      `CursorHider` (`grep -rn "NSCursor\.\(hide\|unhide\)"`)
- [x] every exit path (animated close, non-animated close, fullscreen
      exit, PiP enter/exit, app switch, deinit) releases the hide
- [x] run `swift test` in `packages/FoundationUtils`
- [x] run the Debug app build

### Task 6: [Final] Update documentation
- [x] mention `swift test` in `packages/FoundationUtils` in `INSTALL.md`
      Notes if useful
- [x] move this plan to `docs/plans/completed/` (deferred to orchestrator after reviews)

### ➕ Task 7: Address review findings

**Files:**
- Create: `packages/FoundationUtils/Sources/FoundationUtils/CursorIdleController.swift`
- Create: `packages/FoundationUtils/Tests/FoundationUtilsTests/CursorIdleControllerTests.swift`
- Modify: `SVideoController.swift`, `GalleryViewer.swift`,
  `MGalleryVideoItem.swift`, `PIPVideoWindow.swift`, `CursorHider.swift`

- [x] restore master's fullscreen focus model; split visible host and
      focus owner in the idle check and focus observers
- [x] extract `CursorIdleController` with an injected scheduler and test
      it (`CursorIdleControllerTests`)
- [x] end appearance on PiP close; leave fullscreen on non-animated close
- [x] drop the no-op cursor hide on fullscreen mouse down/up
- [x] tighten `CursorHider` tests (weak deinit check, condition count)
- [x] run `swift test` and the app build — must pass

## Post-Completion
*Manual verification in the running app*

- Fullscreen video playing: wait 1s (cursor hides), click without
  moving, wait 1s, press Esc twice with waits between → cursor visible in
  the chat window.
- Open a short (<30s, looping) video, let the cursor hide, close the
  gallery → cursor visible; wait for several loop intervals → still
  visible.
- Close the gallery through a non-animated path (e.g. enter PiP, or log
  out while the viewer is open) → cursor visible.
- With a video playing, Cmd-Tab away and back with the pointer still →
  cursor visible, then hides after 1s idle over the video.
- Enter fullscreen with keyboard/menu, pointer still over the video →
  cursor hides after 1s; exit fullscreen with the pointer still →
  same behaviour in the gallery window.
- In fullscreen, Space pauses/plays, F and Esc exit fullscreen, arrows
  seek or switch items; the cursor still hides after 1s idle.
- Close PiP with its close button → cursor visible; app activations do
  not rearm the closed player.
- PiP: leave the pointer still over the PiP window → controls fade after
  1s, cursor stays visible.
- Non-animated close while the controller stays retained (e.g. a looping
  short video entering PiP, or log out with the viewer open) → cursor
  visible and stays visible across loop completions.
- Move the pointer out of the video onto another Telegram window → cursor
  stays visible.
