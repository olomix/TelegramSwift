# Rename the App to Telex and Replace Its Icon

## Overview
- Show the fork as **Telex** wherever the app names itself: `Telex.app`,
  Dock, menu bar, About window, alert headers, login title, Share menu and
  the fork's own messages.
- Replace the app icon with the chosen `09-plane-sunset` design.
- Keep the bundle IDs (`dev.alek.telegram*`), the app group, Xcode target
  and scheme names, and the Swift module name, so existing local data and
  logins survive and upstream merges stay small.
- Telegram's API terms forbid "Telegram" in a third-party client's name;
  this also makes the fork easy to tell apart from the official client.

## Context (from discovery)
- App target `Telegram` (`Telegram.xcodeproj`; `productName` is
  `Telegram-Mac`, `pbxproj:7111`) has `PRODUCT_NAME = "$(TARGET_NAME)"`,
  so it builds `Telegram.app` with executable `Telegram`. Its build
  configurations are `D098C7241D7E175A007784E4` (Debug) and
  `C232EA261E1BC1A100C4D38C` (Release). `Telegram-Mac/Info.plist` reads
  `CFBundleName` from `$(PRODUCT_NAME)`.
- `Debug.xcconfig`/`Release.xcconfig` (and `common.xcconfig`) are shared by
  all targets, so the product name must be set on the app target only.
- The module name must stay `Telegram`: `MainMenu.xib` uses
  `customModule="Telegram"` 52 times, and code matches runtime class names
  with the module prefix (`"Telegram.OpmizeDatabaseView"` in
  `AppDelegate.swift:723,728,1155,1222`; `"Telegram.GeneralRowItem"` in
  `PeerMediaController.swift:1668,1671` and
  `StorageUsageBlockController.swift:488`).
- Nothing finds the app by bundle or executable name: keychain, URL
  schemes, TCC and notifications use the bundle ID; `AppRelauncher` and
  `Dock` use `Bundle.main.bundlePath`.
- `appName = "Telegram"` in `Telegram-Mac/System.swift:22` feeds the About
  window, alert headers and the login title.
- Menu titles are set at runtime from `Localizable.strings`, keyed by xib
  IDs: `1Xt-HY-uBw.title` and `uQy-DD-JDr.title` (app menu, now
  "Telegram"), `5kV-Vb-QxS.title` (About), `Cag-YX-WT6.title` (Hide),
  `4sb-4s-VLi.title` (Quit). Only `Base.lproj/MainMenu.xib` is in the
  project; the other `*.lproj/MainMenu.xib` copies are unused.
- `Telegram-Mac/en.lproj/Localizable.strings` is **UTF-16 LE**. Edit it with
  a tool that keeps the encoding (e.g. `iconv` to UTF-8, edit, `iconv`
  back), and check with `file` and `plutil -lint` afterwards.
- `TelegramShare/Info.plist` sets `CFBundleDisplayName = Telegram`. Only
  `TelegramShare.appex` is embedded in the app; FocusIntents is not embedded.
- Icon: `Telegram-Mac/Assets.xcassets/AppIcon.appiconset`, ten PNGs
  `Logo_16.png` … `Logo_1024.png` listed in `Contents.json`. The chosen
  SVG is already at `images/AppIcon.svg`.
- Schemes (`Telegram`, `Release`, `TelegramShare`) store
  `BuildableName = "Telegram.app"`.
- `DockControl.swift:84-95` re-applies a previously chosen alternate Dock
  icon at every launch, which would hide the new icon.
- Docs and scripts that name `Telegram.app`: `INSTALL.md`,
  `scripts/check-package-assets.swift` (usage text), and upstream CI
  scripts `buildbox/build-mac.sh`, `buildbox/internal.sh` (left as is).
- Tools available: `rsvg-convert`, `magick`, `shellcheck`.

## Development Approach
- **testing approach**: Regular. This change is build settings, assets and
  strings with no new logic, so each task is checked by building the app
  and inspecting the built bundle instead of unit tests.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task ends with its verification checks passing**
- **CRITICAL: update this plan file when scope changes during implementation**
- keep the bundle IDs, app group, target names and module name unchanged

## Testing Strategy
- No unit-test target covers the app bundle; verification is a Debug build
  plus `plutil`/`ls`/`pluginkit` checks against the built `Telex.app`.
- Build command:
  ```
  xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath ~/build/TelegramSwift \
    -allowProvisioningUpdates build
  ```
- Run `shellcheck` on the new icon script.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update plan if implementation deviates from original scope

## Solution Overview
- Set `PRODUCT_NAME = Telex` in the app target's Debug and Release build
  settings and pin `PRODUCT_MODULE_NAME = Telegram` next to it. The bundle,
  executable and `CFBundleName` become Telex, while xib module references
  and class-name lookups keep working.
- Change the hard-coded app name in one place (`appName`), the app-menu
  strings and xib titles, and the fork-authored messages.
- Keep the icon SVG in the repo with a small script that renders all ten
  PNG sizes under the existing file names, so `Contents.json` stays as it is
  and the icon can be regenerated.

## Technical Details
- Icon sizes (file → pixels): `Logo_16` 16, `Logo_32` 32, `Logo_32-1` 32,
  `Logo_64` 64, `Logo_128` 128, `Logo_256` 256, `Logo_256-1` 256,
  `Logo_512` 512, `Logo_512-1` 512, `Logo_1024` 1024.
- The SVG is drawn on the macOS 1024 grid (824 px tile, 100 px margin,
  drop shadow), so no extra padding is needed.
- Known limitations (out of scope):
  - language packs downloaded from Telegram's servers name the app
    "Telegram"; only the app-menu, About, Hide and Quit titles are patched
    (`MMMenuItem.swift`), other pack strings keep "Telegram";
  - upstream strings that name the app keep "Telegram": permission prompts
    (`Localizable.strings:3601,3610,3611,5189,5190,5602`),
    `Telegram.UpgradeDatabase.Text` (`:4230`), the log-out text (`:4139`),
    `AppUpdateViewController.swift:94`;
  - the "Default" entry in Settings > Appearance > App Icon is a server
    `Default.icns` with Telegram's logo (`DockControl.swift:38`);
  - copyright lines, "TELEGRAM MESSENGER" in `AboutModalController.swift:38`
    and `Spotlight.swift:49` credit upstream or are not user-visible.

## What Goes Where
- **Implementation Steps**: project settings, schemes, strings, icon
  assets, script and docs in this repo.
- **Post-Completion**: manual checks in Finder/Dock.

## Implementation Steps

### Task 1: Render the icon from the SVG

**Files:**
- Create: `scripts/render-app-icon.sh`
- Modify: `Telegram-Mac/Assets.xcassets/AppIcon.appiconset/*.png`

- [x] write `scripts/render-app-icon.sh` that renders `images/AppIcon.svg`
      with `rsvg-convert` into each size from Technical Details in
      `Telegram-Mac/Assets.xcassets/AppIcon.appiconset`, failing early if
      `rsvg-convert` is missing; resolve paths from the script location
- [x] run `shellcheck scripts/render-app-icon.sh`; fix all findings
- [x] run the script and check with `sips -g pixelWidth -g pixelHeight` that
      each of the ten PNGs has the expected size
- [x] view `Logo_1024.png` and `Logo_32.png` to confirm they look right

### Task 2: Rename the built product to Telex

**Files:**
- Modify: `Telegram.xcodeproj/project.pbxproj`
- Modify: `Telegram.xcodeproj/xcshareddata/xcschemes/Telegram.xcscheme`
- Modify: `Telegram.xcodeproj/xcshareddata/xcschemes/Release.xcscheme`
- Modify: `Telegram.xcodeproj/xcshareddata/xcschemes/TelegramShare.xcscheme`

- [x] in the `Telegram` target's configurations
      `D098C7241D7E175A007784E4` and `C232EA261E1BC1A100C4D38C`, set
      `PRODUCT_NAME = Telex` and `PRODUCT_MODULE_NAME = Telegram`; leave the
      extension targets alone
- [x] rename the product file reference `Telegram.app` → `Telex.app`
      (`path` and comments)
- [x] update `BuildableName = "Telegram.app"` → `"Telex.app"` in the three
      schemes
- [x] build Debug; it must succeed
- [x] verify the built bundle: `Telex.app/Contents/MacOS/Telex` exists,
      `plutil -extract CFBundleName raw` prints `Telex`, and
      `CFBundleIdentifier` is still `dev.alek.telegram`
- [x] verify `Telex.app/Contents/PlugIns/TelegramShare.appex` exists with
      bundle ID `dev.alek.telegram.TelegramShare`

### Task 3: Use Telex in in-app name strings

**Files:**
- Modify: `Telegram-Mac/System.swift`
- Modify: `Telegram-Mac/MMMenuItem.swift`
- Modify: `Telegram-Mac/Base.lproj/MainMenu.xib`
- Modify: `Telegram-Mac/en.lproj/Localizable.strings`
- Modify: `TelegramShare/Info.plist`

- [x] set `appName = "Telex"` in `Telegram-Mac/System.swift`
- [x] in `Base.lproj/MainMenu.xib` only, change titles `About Telegram`,
      `Hide Telegram`, `Quit Telegram`, menu `TelegramMac` and window
      `Telegram` to Telex; don't touch `customModule` attributes or other
      `*.lproj/MainMenu.xib` copies
- [x] in `en.lproj/Localizable.strings` (keep UTF-16 LE), set
      `1Xt-HY-uBw.title` and `uQy-DD-JDr.title` to `Telex`, and
      `5kV-Vb-QxS.title`, `Cag-YX-WT6.title`, `4sb-4s-VLi.title` to
      About/Hide/Quit Telex
- [x] in the same file, say Telex in the fork-authored strings
      `ShareExtension.Unauthorized.Description` (also fix the "Telegam"
      typo), `ShareExtension.Setup.Description` and
      `ApiCredentials.RelaunchFailed`
- [x] check `file` still reports UTF-16 and `plutil -lint` passes
- [x] ➕ replace "Telegram" with `appName` in the app-menu, About, Hide and
      Quit titles in `MMMenuItem.swift`: the downloaded language pack (also
      for English) overrides the bundled strings, so the menu kept saying
      Telegram
- [x] set `CFBundleDisplayName` to `Telex` in `TelegramShare/Info.plist`
- [x] build Debug; it must succeed
- [x] run the app and check that the app menu says Telex and About/Hide/Quit
      Telex, the About window says Telex, and an existing account is still
      logged in

### Task 4: Update docs and script references
- [x] update `INSTALL.md` paths (`Telex.app`, `Contents/MacOS/Telex`) and
      mention `scripts/render-app-icon.sh` for regenerating the icon
- [x] update usage text in `scripts/check-package-assets.swift` to
      `<path/to/Telex.app>`
- [x] update `README.md` if it names the app (left as is - it describes
      the official upstream app, not the fork's build)

### Task 5: Verify acceptance criteria
- [x] delete the old `~/build/TelegramSwift/Build/Products/Debug/Telegram.app`
      so LaunchServices doesn't see two bundles with the same ID (already
      gone; pid 15950 still runs from the deleted bundle and was left alone)
- [x] run `pluginkit -m -v -i dev.alek.telegram.TelegramShare` and confirm
      the path is inside `Telex.app` (registered with `pluginkit -a`, but
      pluginkit still elects the same-version copy in the stale Xcode
      DerivedData `Telegram.app`; manual step: delete
      `~/Library/Developer/Xcode/DerivedData/Telegram-Mac-*` and
      `~/build/TelegramSwift/Build/Products/Release/Telegram.app`)
- [x] in Settings > Appearance > App Icon, pick Default if a custom icon is
      set, then relaunch (skipped - setting not changed by automation;
      `Telex.app` has no custom Finder icon xattr)
- [x] confirm the Dock, menu bar, Finder (`Telex.app`) and Cmd-Tab show
      Telex with the new icon (run `killall Dock` if it shows a cached icon)
      (Finder icon and menu titles verified; Dock/Cmd-Tab skipped - screen
      locked, needs a human; `killall Dock` left as a manual step)
- [x] confirm the Share menu lists Telex; if it shows the old icon, replace
      `TelegramShare/icon.icns` too (appex `CFBundleDisplayName` is Telex and
      its icon resolves to the new app icon, since its Info.plist sets no
      icon file; Share menu itself skipped - screen locked)
- [x] confirm `git grep -n "Telegram\.app"` hits only `buildbox/*`,
      `AppUpdateViewController.swift` (update zip name, unused since Sparkle
      was removed) and `docs/plans/completed/`
- [x] run `swift scripts/check-package-assets.swift
      ~/build/TelegramSwift/Build/Products/Debug/Telex.app`

### Task 6: [Final] Close the plan
- [x] update CLAUDE.md if new patterns were discovered (added a short root CLAUDE.md: module name pin, UTF-16 strings, language pack menu titles)
- [x] move this plan to `docs/plans/completed/` (done by the exec completion step)

## Post-Completion
*Items requiring manual intervention or external systems - no checkboxes, informational only*

**Manual verification**:
- Notification permission is tied to the bundle ID, so it should carry
  over; re-enable it in System Settings if notifications stop.
