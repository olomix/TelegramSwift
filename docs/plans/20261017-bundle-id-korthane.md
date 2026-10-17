# Change the bundle ID to com.korthane.telex

## Overview
- Change the bundle ID from `dev.alek.telegram` to `com.korthane.telex`,
  for the app and its extensions. The app group (data folder) changes
  with it: `$(TeamIdentifierPrefix)com.korthane.telex`.
- Why now: the switch to the new signing team (2FKX9S8MFA) already moved
  the app group to an empty folder, so everyone logs in again anyway.
  The app's info will live at telex.korthane.com, so the ID follows
  that domain.
- Start fresh: remove the startup step that moves data from
  `~/Library/Application Support/<bundle ID>/` into the app group. With
  the new ID that folder never held account data, so the step is dead
  code. Call logs already go to `<account>/calls` inside the app group
  (`callLogsPath` in `OngoingCallContext.swift`); the `voip.log` path in
  `Telegram-Mac/CallBridge.mm` is dead code (the file is not in the Xcode
  project), so nothing writes to `Application Support` any more.

## Context (from discovery)
- Bundle IDs in `Telegram.xcodeproj/project.pbxproj`:
  `dev.alek.telegram` (Debug + Release of the app),
  `dev.alek.telegram.TelegramShare`, `dev.alek.telegram.FocusIntents`.
- App group `$(TeamIdentifierPrefix)dev.alek.telegram` in
  `Telegram-Mac/Info.plist` and `TelegramShare/Info.plist` (`TGAppGroup`),
  `Telegram-Mac/Telegram-Mac.entitlements`,
  `Telegram-Mac/Telegram-Sandbox.entitlements`,
  `TelegramShare/TelegramShare.entitlements`.
- `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`:
  `ApiEnvironment.bundleId`, the `appGroup` doc comment,
  `legacyDataRootURL`.
- Migration code: `packages/ApiCredentials/Sources/ApiCredentials/DataFolderMigration.swift`,
  its tests `DataFolderMigrationTests.swift`, and in
  `Telegram-Mac/AppDelegate.swift` `moveLegacyDataIntoAppGroup()`,
  `showDataMoveFailedAlert()` and the guard that calls them in
  `applicationDidFinishLaunching`.
- Test strings in `packages/ApiCredentials/Tests/ApiCredentialsTests/AppGroupTests.swift`.
- `INSTALL.md`: app ID in the intro, the app group path, the
  "Older builds kept data in Application Support" note, the `pluginkit`
  command.
- Completed plans in `docs/plans/completed/` keep the old ID as history.
- Side effects, no action needed: `ApiEnvironment.bundleId` is sent to
  Telegram's servers in `appData`; `intentsBundleId` changes with it (its
  only reader in the app is commented out). `Info.plist` IDs, the `tg`
  handler, the reopen notification and touch bar IDs already come from
  `PRODUCT_BUNDLE_IDENTIFIER` / `Bundle.main.bundleIdentifier`. No
  keychain group, iCloud or push entitlement uses the ID.

## Development Approach
- **testing approach**: Regular
- complete each task fully before moving to the next
- small, focused commits; plain commit messages, no prefixes
- update this plan if scope changes

## Testing Strategy
- **unit tests**: `cd packages/ApiCredentials && swift test`
- **build check**: `xcodebuild -workspace Telegram-Mac.xcworkspace -scheme
  Telegram -configuration Debug -destination 'platform=macOS,arch=arm64'
  -derivedDataPath ~/build/TelegramSwift build`
- **signed IDs check**: on the built app, `codesign -d --entitlements -`
  and `plutil -p .../Info.plist` show the new IDs for Telex.app and
  TelegramShare.appex.
- **e2e**: none in the project; manual checks in Post-Completion.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Solution Overview
- A plain rename of every `dev.alek.telegram` in build settings, plists,
  entitlements, code and INSTALL.md, then delete the migration code.
- Keep the team-prefixed app group form (`<TeamID>.com.korthane.telex`):
  on macOS it needs no registered `group.` identifier, and
  `AppGroup.isTeamPrefixed` already checks it.
- Out of scope: `ApiEnvironment.teamId` (`6N38VWS5BX`, upstream's team,
  used only for the FocusIntents defaults suite); target, scheme and
  module names (CLAUDE.md says keep them).

## Technical Details
- Old → new:
  - `dev.alek.telegram` → `com.korthane.telex`
  - `dev.alek.telegram.TelegramShare` → `com.korthane.telex.TelegramShare`
  - `dev.alek.telegram.FocusIntents` → `com.korthane.telex.FocusIntents`
  - `$(TeamIdentifierPrefix)dev.alek.telegram` →
    `$(TeamIdentifierPrefix)com.korthane.telex`
- After the change, `git grep dev.alek -- ':!submodules' ':!docs/plans'`
  finds only the old-folder list in INSTALL.md.
- `applicationDidFinishLaunching` starts with the app lock, then goes on
  with the rest of startup; no data-move step.

## What Goes Where
- **Implementation Steps**: code, build settings, tests, INSTALL.md.
- **Post-Completion**: deleting old data folders on developer machines,
  manual launch checks.

## Implementation Steps

### Task 1: Rename the bundle IDs and app group

**Files:**
- Modify: `Telegram.xcodeproj/project.pbxproj`
- Modify: `Telegram-Mac/Info.plist`
- Modify: `TelegramShare/Info.plist`
- Modify: `Telegram-Mac/Telegram-Mac.entitlements`
- Modify: `Telegram-Mac/Telegram-Sandbox.entitlements`
- Modify: `TelegramShare/TelegramShare.entitlements`
- Modify: `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`
- Modify: `packages/ApiCredentials/Tests/ApiCredentialsTests/AppGroupTests.swift`

- [x] replace the 6 `PRODUCT_BUNDLE_IDENTIFIER` values in project.pbxproj
- [x] replace the app group in both Info.plists and the 3 entitlements files
- [x] change `ApiEnvironment.bundleId` and the `appGroup` doc comment
- [x] update the ID strings in `AppGroupTests.swift` (same format cases,
      new ID; they test the format, not the ID itself)
- [x] run `cd packages/ApiCredentials && swift test` - must pass
- [x] run the build check; check the built Telex.app and
      TelegramShare.appex carry the new bundle IDs and app group

### Task 2: Remove the legacy data move

**Files:**
- Delete: `packages/ApiCredentials/Sources/ApiCredentials/DataFolderMigration.swift`
- Delete: `packages/ApiCredentials/Tests/ApiCredentialsTests/DataFolderMigrationTests.swift`
- Modify: `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`
- Modify: `Telegram-Mac/AppDelegate.swift`

- [x] delete `moveLegacyDataIntoAppGroup()` with its doc comment,
      `showDataMoveFailedAlert()` and their guard in
      `applicationDidFinishLaunching`; it then reads: app lock →
      `observeReopenRequests()` → rest of startup
- [x] delete `ApiEnvironment.legacyDataRootURL`
- [x] delete `DataFolderMigration.swift` and its tests
- [x] check nothing else references them (`git grep`)
- [x] run `cd packages/ApiCredentials && swift test` - must pass
- [x] run the build check - must pass

### Task 3: Update INSTALL.md
- [x] new ID in the intro and the app group path
- [x] replace the "Older builds kept data in Application Support" note
      with: the bundle ID changed to `com.korthane.telex`, so log in again
      and delete the old folders (same list as Post-Completion)
- [x] reword the "Builds before the rename made `Telegram.app` with the
      same bundle ID" paragraph: old `Telegram.app` and old-ID `Telex.app`
      copies now have a different ID, so they only leave stale Share and
      Dock entries; delete them. New ID in the `pluginkit` command
- [x] update CLAUDE.md if needed (it names no bundle ID today)

### Task 4: Verify acceptance criteria
- [x] `git grep dev.alek -- ':!submodules' ':!docs/plans/completed'`
      finds nothing (only expected hits: the old-folder list in INSTALL.md
      from Task 3, plus this plan)
- [x] run `cd packages/ApiCredentials && swift test` and the build check
- [x] launch the Debug build from the terminal; it creates
      `~/Library/Group Containers/<TeamID>.com.korthane.telex/debug/` and
      `app.lock`, and shows the login screen; quit it (do not kill any
      process you did not start) (first screen is the fork's API
      credentials form, shown before login on a fresh data folder)
- [x] move this plan to docs/plans/completed/ (done by the exec completion step)

## Post-Completion
*Manual, on each developer machine*

**Delete the old data** (quit every Telex/Telegram build first; the old
ID's data is never read again):
- `~/Library/Group Containers/3PB2Z94Q5T.dev.alek.telegram` (old team)
- `~/Library/Group Containers/2FKX9S8MFA.dev.alek.telegram` (new team,
  old ID)
- `~/Library/Application Support/dev.alek.telegram` (pre-app-group data)
- sandbox containers: `~/Library/Containers/dev.alek.telegram`,
  `~/Library/Containers/dev.alek.telegram.TelegramShare`,
  `~/Library/Containers/dev.alek.telegram.FocusIntents`
- `~/Library/Caches/dev.alek.telegram`
- `~/Library/HTTPStorages/dev.alek.telegram`
- `~/Library/WebKit/dev.alek.telegram`
- `~/Library/Saved Application State/dev.alek.telegram.savedState`
- preferences: `defaults delete dev.alek.telegram` (then the plist in
  `~/Library/Preferences` is gone too)
- privacy grants (camera, microphone, location):
  `tccutil reset All dev.alek.telegram`
- Spotlight items indexed under the old ID stay until macOS drops them.
- macOS may refuse to delete Group Containers / Containers from the
  terminal ("Operation not permitted"); delete them in Finder, or give the
  terminal Full Disk Access.
- Back up a folder first if you still need anything in it.

**Manual checks**:
- Log in with the Debug build; the Share extension (`pluginkit -m -v -i
  com.korthane.telex.TelegramShare`) finds the logged-in account.
- Release build: logs in, runs sandboxed, uses `stable/`.
- The single-instance guard still refuses a second copy (lock now at
  `<TeamID>.com.korthane.telex/app.lock`).
- Camera, microphone and location prompts appear again on first use
  (grants are per bundle ID).
