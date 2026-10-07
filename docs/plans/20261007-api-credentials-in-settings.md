# API credentials in app settings

## Overview
- Today `api_id` and `api_hash` are compiled in from `Secrets.xcconfig`
  through Info.plist, and the app calls `fatalError` without them. A user of
  a prebuilt copy of this fork cannot run it without rebuilding.
- Move both values into a settings screen. The user enters their own values
  from my.telegram.org once; the app stores them and checks them against
  Telegram's servers before accepting them.
- First launch: a blocking "API credentials" popup opens over the main
  window before the app connects anywhere. It closes only after the values
  pass the server check.
- Every later launch: the app re-checks the stored values in the background.
  If Telegram rejects them, the same blocking popup opens (over the login
  screen, or over the Settings tab when logged in) until working values are
  saved; then the app relaunches.
- Settings gets an "API credentials" row (next to Proxy) to change the values
  later. Saving new values relaunches the app.
- Bad fields are outlined in red with a note: "Required" (empty), "Enter the
  numeric api_id" / "Enter the 32-character api_hash" (malformed), or
  "Telegram rejected these values" (both fields); the screen shows a hint
  with a link: "Get your api_id and api_hash at my.telegram.org → API
  development tools".
- If Telegram can't be reached at all (offline, or a network that needs a
  proxy), an alert says so and offers "Try again" and "Save anyway" for
  well-formed values;
  the next launch's background check catches values that turn out wrong.
  Being offline never locks the user out.
- Server addresses and public keys are NOT configurable: the production
  values listed on my.telegram.org are already built into MtProtoKit /
  TelegramCore (`Network.swift` seed list), and changing them would mean
  editing the telegram-ios submodule.
- The Share extension (the "Telegram" item in the macOS Share menu) is
  sandboxed and currently cannot see the app's data at all, since data moved
  to `~/Library/Application Support/dev.alek.telegram`. Move all app data into
  an app group container named after this fork's bundle ID, so the extension
  reads the same accounts and credentials. The group is
  `<TeamID>.dev.alek.telegram`, separate from the official client's group.

## Context (from discovery)
- `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`:
  `ApiEnvironment.apiId` / `apiHash` read `TGApiId` / `TGApiHash` from
  Info.plist and `fatalError` when missing; `dataRootURL` / `containerURL`
  point at Application Support, and `containerURL` creates `<root>/<prefix>`
  on every access. Upstream used
  `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` and had
  a `migrate()` (removed in d92d8517b).
- Credential readers: `Telegram-Mac/AppDelegate.swift:816`
  (`NetworkInitializationArguments`), `Telegram-Mac/AuthController.swift:745`
  and `:1082`, `TelegramShare/ShareViewController.swift:129`.
- Data path users: `AppDelegate.swift:374`, `UNUserNotifications.swift:309`
  (`dataRootURL`), `CoreExtension.swift`, `DockControl.swift`,
  `FetchCachedRepresentations.swift`, `DeveloperViewController.swift`,
  `packages/TelegramMedia/Sources/LottieBufferCompressor.swift` (started by
  `startLottieCacheCleaner()` at `AppDelegate.swift:371`, creates
  `containerURL/trlottie-animations/`), `TelegramShare/ShareViewController.swift:43,114`.
- Launch flow: `applicationDidFinishLaunching` → `launchInterface()`
  (`AppDelegate.swift:501`) creates the `accountManager` (`:513`), then
  branches on `appEncryption.decrypt()` (`:515`) into the passcode modal or
  `launchApp`, which builds the network (~`:816`).
- Blocking modal precedent: `Telegram-Mac/ColdStartPasslockController.swift`
  (`closable` `:86`, `escapeKeyAction` `:91`).
- Build wiring: `TG_API_ID` / `TG_API_HASH` in
  `Telegram-Mac/Secrets.example.xcconfig`, comment at
  `Telegram-Mac/common.xcconfig:19`, `TGApiId` / `TGApiHash` in
  `Telegram-Mac/Info.plist` and `TelegramShare/Info.plist`, INSTALL.md.
- Signing: Release configs of Telegram (`project.pbxproj:8954`, sandboxed
  with `Telegram-Sandbox.entitlements`, `CODE_SIGN_IDENTITY = ""` at
  `:8949`) and TelegramShare (`:9070`) set `DEVELOPMENT_TEAM = ""` at target
  level, overriding `Secrets.xcconfig`. No entitlements file declares an app
  group today.
- Server check: `auth.exportLoginToken` carries both `api_id` and `api_hash`
  and has no side effect (no SMS). Public TelegramCore API:
  `accountWithId(...)` (`Account.swift:255`) → `.unauthorized(UnauthorizedAccount)`,
  `TelegramEngineUnauthorized(account:).auth.exportAuthTransferToken(...)`.
  A 400 `API_ID_INVALID` fails fast as `ExportAuthTransferTokenError.generic`;
  offline and FLOOD_WAIT retry silently, so "no answer in time" means
  unreachable. `accountWithId` reads `ProxySettings` from the account manager
  it is given (`Account.swift:278-281`).
- Strings: `Telegram-Mac/en.lproj/Localizable.strings`; accessors in
  `packages/Localization/Sources/Localization/Localizable.swift` are
  generated by `tools/swiftgen.sh`.
- New app source files must be added to `Telegram.xcodeproj/project.pbxproj`
  (no synchronized folders in this project).
- Out of scope: `ApiEnvironment.teamId = "6N38VWS5BX"` (used only for the
  FocusIntents bundle ID) and `BuildConfig.m:301` keep Telegram's team ID.
- Tests: the only test target is `packages/FoundationUtils`. Logic is
  extracted into the `ApiCredentials` package and tested with `swift test`.

## Development Approach
- **testing approach**: Regular — code first, then tests. Logic without
  AppKit/TelegramCore goes into the `ApiCredentials` package and is unit
  tested; app wiring is verified by building and the Post-Completion checks.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in
  that task
- **CRITICAL: all tests must pass before starting next task** - no exceptions
- **CRITICAL: update this plan file when scope changes during implementation**
- Build the app after every task that touches app code:
  `xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram
  -configuration Debug -destination 'platform=macOS,arch=arm64'
  -derivedDataPath ~/build/TelegramSwift build`.
  Each build bumps `CFBundleVersion` in both Info.plists. Note the value
  before building and restore only that key afterwards, e.g.
  `/usr/libexec/PlistBuddy -c "Set :CFBundleVersion <old>" Telegram-Mac/Info.plist`
  (same for `TelegramShare/Info.plist`), so this plan's own plist edits stay.
- Do not modify anything under `submodules/`.

## Testing Strategy
- **unit tests**: `cd packages/ApiCredentials && swift test`, required for
  every task that adds logic to the package.
- **e2e tests**: none in this project; manual checks in Post-Completion.
- After the final build also run
  `swift scripts/check-package-assets.swift ~/build/TelegramSwift/Build/Products/Debug/Telegram.app`
  and `cd packages/FoundationUtils && swift test`.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update plan if implementation deviates from original scope
- keep plan in sync with actual work done

## Solution Overview
- **Storage**: `ApiCredentialsStore` keeps `{ "apiId": Int32, "apiHash":
  String }` in `api-credentials.json` at the root of the app group container
  (mode 0600). Both the app and the Share extension read it. The api_hash is
  an app identifier, not a user secret, so a file is enough (no Keychain).
- **Validation**: api_id is a positive Int32; api_hash is 32 hex characters
  (surrounding whitespace trimmed, upper case accepted and stored lower
  case). Format errors are shown per field before any network call.
- **Server check** (`ApiCredentialsChecker`, app side): creates an
  `UnauthorizedAccount` with `accountWithId` using the app's real
  `accountManager` (so the user's proxy settings apply), a fresh record ID,
  a temporary `rootPath` and `shouldKeepAutoConnection: false`; sends
  `auth.exportLoginToken` directly through `account.network.request` (the
  engine wrapper hides the error text): any answer → `.accepted`;
  `API_ID_INVALID` / `API_ID_PUBLISHED_FLOOD` → `.rejected`
  (`ApiCredentialsCheckResult(serverError:)`, pure, in the package); any
  other error or no answer within 15 s → `.unreachable`. On completion or
  dispose it drops the account and deletes the temporary folder; each check
  also sweeps leftover folders of earlier checks.
- **Startup decision** (in `launchInterface()`): no stored values → blocking
  modal before launch; stored values → launch and check in the background;
  only a background `.rejected` blocks. The credentials are read once there
  and passed down to the network arguments; the auth screens use the
  account's `networkArguments`.
- **UI**: one `ApiCredentialsController` (TGUIKit input-data style, like the
  proxy settings screen) used in two hosts:
  1. blocking modal (`showModal`, `closable = false`, Esc ignored, like
     `ColdStartPasslockController`) — for first launch and for a rejected
     background check;
  2. normal pushed screen from the Settings "API credentials" row.
  "Save" validates format, then runs the server check with a progress
  indicator. `.rejected` marks both fields red with "Telegram rejected these
  values". `.unreachable` shows "Couldn't reach Telegram" with "Try again"
  and "Save anyway". The popup after a rejected background check opens with
  both fields already marked.
- **Launch gate**: in `launchInterface()` after the `accountManager` is
  created (`:513`) and before `appEncryption.decrypt()` (`:515`). With no
  stored values, load the theme as the passcode branch does (`:520-532`),
  show the blocking modal, and resume the normal branch when it saves.
  With stored values, launch normally and start the background check; on
  `.requireBlocking`, select the Settings tab if an account is logged in and
  show the blocking modal; on save, relaunch. Settings relaunches only when
  the saved values differ from the account's running `networkArguments`.
- **Relaunch**: spawn `/bin/sh -c 'cat >/dev/null; open "$1"'` with its
  stdin on a pipe whose write end the app keeps open, then
  `NSApp.terminate`; the helper reads end-of-file once the app has exited,
  so two copies never share the database. A pipe is used instead of
  `kill -0 <pid>` because the App Sandbox may deny signalling the app.
- **Data folder**: `ApiEnvironment.dataRootURL` becomes the app group
  container. Its identifier `$(TeamIdentifierPrefix)dev.alek.telegram` is
  written into both Info.plists (`TGAppGroup`) at build time. A guard rejects
  an identifier without a 10-character team prefix with a clear
  `fatalError` (build without a team), instead of silently using a folder
  the extension cannot reach. When the system cannot resolve the group
  container, the app shows an alert and quits instead of a blank window.
- **Migration**: as the very first line of `applicationDidFinishLaunching`
  (before `startLottieCacheCleaner()` at `:371`), move each top-level item of
  `~/Library/Application Support/dev.alek.telegram` into the group container.
  Each item is decided on its own: an existing regular file, or a folder
  with an `account-*` folder inside, is kept; anything else there (hidden
  files, empty folders, an account manager without accounts left by the
  Share extension) is replaced. A second build type or a re-run after a
  partial move still moves what is left. Only Debug (not sandboxed) can do
  this: Release now runs in the App Sandbox, where `legacyDataRootURL`
  resolves inside `~/Library/Containers/dev.alek.telegram/`, so its old
  `stable/` data is moved by a Debug build or by hand (INSTALL.md). No
  temporary-exception entitlement is added for the old path.
- **Share extension**: reads data and credentials from the same group. It
  checks the credentials first, before it touches the group folder; if they
  are missing it shows "Open Telegram to finish setup" instead of starting a
  network.

## Technical Details
- New package files (`packages/ApiCredentials/Sources/ApiCredentials/`):
  - `ApiCredentialsValues.swift` — `struct ApiCredentialsValues: Codable,
    Equatable { apiId: Int32; apiHash: String }`; `static func
    validate(apiId: String, apiHash: String) -> Result<ApiCredentialsValues,
    ApiCredentialsFormatError>` (error lists the bad fields).
    `ApiCredentialsField { apiId, apiHash }` and `ApiCredentialsFormatError`
    (`invalidFields`) live here too.
  - `ApiCredentialsStore.swift` — `init(fileURL:)`, `load() ->
    ApiCredentialsValues?` (nil on missing or corrupt file or values that
    fail `validate`), `save(_:) throws` (atomic write, 0600).
  - `ApiCredentialsCheck.swift` — `enum ApiCredentialsCheckResult { accepted,
    rejected, unreachable }` with `init(serverError:)`.
  - `AppGroup.swift` — `static func isTeamPrefixed(_ identifier: String) ->
    Bool` (`^[A-Z0-9]{10}\.`).
  - `DataFolderMigration.swift` — `static func move(from: URL, to: URL,
    fileManager: FileManager) throws`.
- `Config.swift`: `appGroup` (Info.plist `TGAppGroup`, guarded),
  `dataRootURL` (group container), `credentialsFileURL`, `legacyDataRootURL`
  (old Application Support folder for the migration), `storedCredentials`.
- App files: `Telegram-Mac/ApiCredentialsChecker.swift` (also
  `makeNetworkInitializationArguments(_:)`, shared with `AppDelegate`),
  `Telegram-Mac/ApiCredentialsController.swift` (form, field problems,
  blocking modal), `Telegram-Mac/AppRelauncher.swift`;
  `InputDataRowData(outlinesError:)` opts an input row into the red outline.
- Entitlements: add `com.apple.security.application-groups` =
  `[$(TeamIdentifierPrefix)dev.alek.telegram]` to
  `Telegram-Mac/Telegram-Mac.entitlements`,
  `Telegram-Mac/Telegram-Sandbox.entitlements`,
  `TelegramShare/TelegramShare.entitlements`; drop
  `com.apple.developer.maps` from `Telegram-Sandbox.entitlements` (with team
  signing it demands a provisioning profile).
- `project.pbxproj`: remove the target-level `DEVELOPMENT_TEAM = ""` from the
  Release configs of Telegram (`:8954`) and TelegramShare (`:9070`) so they
  inherit from `Secrets.xcconfig`, and set their `CODE_SIGN_IDENTITY`
  (including `[sdk=macosx*]`) to "Apple Development" like Debug; add the new
  app source files.
- Strings: add keys to `Telegram-Mac/en.lproj/Localizable.strings` and
  regenerate `Localizable.swift` with `tools/swiftgen.sh`.

## What Goes Where
- **Implementation Steps**: code, package tests, entitlements, plists,
  project file, strings, INSTALL.md.
- **Post-Completion**: running the app with fresh data, real and wrong
  credentials, offline, behind a proxy, Release signing, the Share menu.

## Implementation Steps

### Task 1: Credentials values, validation and file store

**Files:**
- Create: `packages/ApiCredentials/Sources/ApiCredentials/ApiCredentialsValues.swift`
- Create: `packages/ApiCredentials/Sources/ApiCredentials/ApiCredentialsStore.swift`
- Modify: `packages/ApiCredentials/Package.swift` (add `ApiCredentialsTests`)
- Create: `packages/ApiCredentials/Tests/ApiCredentialsTests/ApiCredentialsValuesTests.swift`
- Create: `packages/ApiCredentials/Tests/ApiCredentialsTests/ApiCredentialsStoreTests.swift`

- [x] add `ApiCredentialsValues` with `validate(apiId:apiHash:)`
- [x] add `ApiCredentialsStore` (load/save/remove, atomic write, 0600)
- [x] add the test target to `Package.swift`
- [x] write tests for valid input (incl. whitespace and upper-case hash) and
      the store round trip
- [x] write tests for bad id (empty, 0, negative, letters, overflow), bad
      hash (short, long, non-hex), missing file, corrupt JSON, file mode 0600
- [x] run `cd packages/ApiCredentials && swift test` - must pass

### Task 2: Check outcome mapping and startup gate

**Files:**
- Create: `packages/ApiCredentials/Sources/ApiCredentials/ApiCredentialsCheck.swift`
- Create: `packages/ApiCredentials/Tests/ApiCredentialsTests/ApiCredentialsCheckTests.swift`

- [x] add result/outcome enums, `checkTimeout` and `ApiCredentialsGate`
- [x] write tests: token → accepted, serverError → rejected, timedOut →
      unreachable
- [x] write tests: no stored values → require before launch; stored →
      launch and check; rejected → blocking; unreachable/accepted → none
- [x] run `swift test` - must pass

### Task 3: Move app data into the app group container

**Files:**
- Create: `packages/ApiCredentials/Sources/ApiCredentials/AppGroup.swift`
- Create: `packages/ApiCredentials/Sources/ApiCredentials/DataFolderMigration.swift`
- Create: `packages/ApiCredentials/Tests/ApiCredentialsTests/AppGroupTests.swift`
- Create: `packages/ApiCredentials/Tests/ApiCredentialsTests/DataFolderMigrationTests.swift`
- Modify: `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`
- Modify: the three entitlements files
- Modify: `Telegram-Mac/Info.plist`, `TelegramShare/Info.plist` (`TGAppGroup`)
- Modify: `Telegram.xcodeproj/project.pbxproj` (Release signing overrides)
- Modify: `Telegram-Mac/AppDelegate.swift` (migration call)

- [x] add `AppGroup.isTeamPrefixed` and `DataFolderMigration.move`
- [x] add the app group entitlement, `TGAppGroup`, and remove the Release
      `DEVELOPMENT_TEAM = ""` / `CODE_SIGN_IDENTITY = ""` overrides
      (Release `CODE_SIGN_IDENTITY` set to "Apple Development" like Debug:
      the project-level value is ad-hoc "-", which cannot carry the group)
- [x] point `dataRootURL` at the guarded group container; add
      `legacyDataRootURL` and `credentialsFileURL`
- [x] call the migration as the first line of `applicationDidFinishLaunching`
- [x] write tests: team prefix accepted / rejected (`dev.alek.telegram`,
      lower case, short prefix)
- [x] write migration tests with temp dirs: moves everything into an empty
      destination; still moves when the destination has only hidden files or
      an empty `debug/` folder; skips names that exist; no-op when
      `<prefix>/accounts-metadata` exists; no-op when source is missing
- [x] run `swift test`, build the app, start it once, confirm the data is
      under `~/Library/Group Containers/<TeamID>.dev.alek.telegram` and you
      are still logged in - must pass (tests and build pass; built app and
      TelegramShare.appex carry `3PB2Z94Q5T.dev.alek.telegram`; launch left
      for manual verification)

### Task 4: Read credentials from the store

**Files:**
- Modify: `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`
- Modify: `TelegramShare/ShareViewController.swift`

- [x] make `ApiEnvironment.apiId` / `apiHash` read `ApiCredentialsStore`,
      falling back to the Info.plist values for now (removed in Task 7) so
      the app keeps working until the screen exists
- [x] Share extension: when no credentials are available (stored or, until
      Task 7, the Info.plist fallback), show "Open Telegram
      to finish setup" and do not start the network
- [x] add a test for any new pure helper (none expected beyond the store; none added - the
      new code reads Bundle/files only and reuses tested `validate`/store)
- [x] run `swift test` and build the app - must pass

### Task 5: Server check against Telegram

**Files:**
- Create: `Telegram-Mac/ApiCredentialsChecker.swift`
- Modify: `Telegram.xcodeproj/project.pbxproj` (add the file)
- Modify: `Telegram-Mac/AppDelegate.swift` (use the shared
  `makeNetworkInitializationArguments`)

- [x] implement `ApiCredentialsChecker.check(_ values:, accountManager:) ->
      Signal<ApiCredentialsCheckResult, NoError>` as in Solution Overview
- [x] release the account and delete the temp folder on completion and on
      dispose
- [x] tests: covered by Task 2's outcome mapping; add cases there if the
      checker needs a new outcome (none needed)
- [x] run `swift test` and build the app - must pass

### Task 6: Credentials screen

**Files:**
- Create: `Telegram-Mac/ApiCredentialsController.swift`
- Modify: `Telegram-Mac/en.lproj/Localizable.strings`
- Modify: `packages/Localization/Sources/Localization/Localizable.swift`
  (regenerated by `tools/swiftgen.sh`)
- Modify: `Telegram.xcodeproj/project.pbxproj` (add the file)
- Modify: `Telegram-Mac/InputDataControllerEntries.swift`,
  `Telegram-Mac/InputDataRowItem.swift` (opt-in red outline on input errors)
- Create: `packages/ApiCredentials/Sources/ApiCredentials/ApiCredentialsFieldProblem.swift`
- Create: `packages/ApiCredentials/Tests/ApiCredentialsTests/ApiCredentialsFieldProblemTests.swift`
  (both later folded into the controller after review, with the
  `ApiCredentialsCheckOutcome` / `ApiCredentialsGate` layers of Task 2)

- [x] build the screen with TGUIKit input-data rows: api_id, api_hash, hint
      with a clickable my.telegram.org link, Save
- [x] red outline and a note on empty, malformed or rejected fields
      ("Required", the per-field format hint, "Telegram rejected these
      values")
- [x] Save flow: validate → check with progress → `.accepted` saves and
      reports to the host; `.rejected` marks fields; `.unreachable` offers
      "Try again" and "Save anyway"
- [x] blocking mode: `closable = false`, Esc ignored (as
      `ColdStartPasslockController`)
- [x] add package tests for any pure helper added (e.g. field error mapping)
- [x] run `swift test` and build the app - must pass

### Task 7: Wire the screen into launch and Settings; drop build-time values

**Files:**
- Modify: `Telegram-Mac/AppDelegate.swift`
- Modify: `Telegram-Mac/AccountViewController.swift`
- Create: `Telegram-Mac/AppRelauncher.swift`
- Modify: `Telegram.xcodeproj/project.pbxproj` (add the file)
- Modify: `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`
- Modify: `Telegram-Mac/Info.plist`, `TelegramShare/Info.plist`
- Modify: `Telegram-Mac/Secrets.example.xcconfig`, `Telegram-Mac/common.xcconfig`

- [x] launch gate in `launchInterface()` before `appEncryption.decrypt()`:
      no stored values → blocking modal, then continue the normal branch
- [x] background check after launch; `.requireBlocking` → select Settings
      tab when logged in, show the blocking modal, relaunch on save
- [x] Settings: "API credentials" row next to Proxy; saving changed values
      relaunches via `AppRelauncher`
- [x] remove the Info.plist fallback, `TGApiId` / `TGApiHash`,
      `TG_API_ID` / `TG_API_HASH` from `Secrets.example.xcconfig`; reword the
      `common.xcconfig` comment and the `Config.swift` `fatalError` messages
- [x] add gate tests for any new decision branch (none added - the wiring
      reuses the existing `ApiCredentialsGate` decisions)
- [x] run `swift test` and build the app - must pass

### Task 8: Verify acceptance criteria
- [x] verify every Overview item is implemented (by code reading: launch
      gate, background check, blocking modal, Settings row, field errors,
      hint link, "Save anyway", app group, Share extension notice)
- [x] verify offline start with stored values never shows the blocking popup
      (by code reading: offline/FLOOD_WAIT retry inside the network layer,
      the 15 s timeout maps to `.unreachable`, and the gate blocks only on
      `.rejected`; runtime check left for manual verification)
- [x] run `cd packages/ApiCredentials && swift test` and
      `cd packages/FoundationUtils && swift test` (39 and 19 tests pass)
- [x] build Debug and Release; run `swift scripts/check-package-assets.swift
      ~/build/TelegramSwift/Build/Products/Debug/Telegram.app` (both
      succeed; 9 package images load; Release app and appex carry
      `3PB2Z94Q5T.dev.alek.telegram`)
- ➕ [x] drop `com.apple.developer.maps` from `Telegram-Sandbox.entitlements`:
      with team signing in Release it demands a provisioning profile and
      the Release build failed; MapKit works without it (Debug never had it)
- [x] `git grep -n "TG_API_ID\|TG_API_HASH\|TGApiId\|TGApiHash"` finds
      nothing outside docs/plans (only INSTALL.md:22 remains, rewritten in
      Task 9)

### Task 9: [Final] Update documentation
- [x] INSTALL.md: drop the credential steps; explain that the app asks for
      api_id / api_hash on first start and where to get them; update the
      data location text (INSTALL.md:61-63) to the group container; state
      that `DEVELOPMENT_TEAM` is required and whether a free personal team
      works (from the Task 3 result)
- [x] mention `cd packages/ApiCredentials && swift test`
- [x] move this plan to docs/plans/completed/ (done by the orchestrator at completion)

## Post-Completion
*Items requiring manual intervention or external systems - no checkboxes,
informational only*

**Manual verification**:
- Fresh start (move the group container and the old Application Support
  folder aside): the popup opens first and cannot be closed; a wrong api_id
  is rejected within a few seconds (not after the 15 s timeout); real values
  pass and the login screen appears.
- Existing install, Debug build: data (both `debug/` and `stable/`) moves
  into the group container and you stay logged in, also when the Share
  menu was opened first.
- Existing install, Release only: the sandboxed build cannot read the old
  folder; follow the manual move in INSTALL.md and confirm you stay logged
  in.
- Relaunch from Settings in a Release (sandboxed) build brings the app back.
- Edit `api-credentials.json` to a wrong hash, start logged in: Settings is
  shown with the blocking popup; fixing it relaunches the app once.
- Start offline with valid stored values: no popup.
- First start on a network that needs a proxy: "Couldn't reach Telegram"
  with "Save anyway".
- Settings → API credentials: change values, the app relaunches with them.
- Share menu → Telegram from Finder: shows your chats; with the credentials
  file removed it says to open Telegram first.
- Release build signed with your team reaches the group container.

**External**:
- Distributing a prebuilt copy needs signing with your Developer ID and
  notarization so other Macs open it; not part of this plan.
