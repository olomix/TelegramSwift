# Move the Mac passcode to upstream PasscodeCore

## Overview
- Replace the Mac's own passcode storage with upstream's `PasscodeCore`
  (Keychain-backed credential, slow key derivation, cooldown enforced
  outside the UI, Touch ID), recorded in the account manager as the
  `.secured` access challenge that upstream's core migrates to.
- Why:
  - **Weak storage today.** `AppEncryptionParameters`
    (`submodules/BuildConfig/Sources/BuildConfig.m`) encrypts the database
    key file `.tempkeyEncrypted` with AES keyed by an unsalted SHA-512 of
    the passcode. A copy of that file lets anyone try every 4-digit code
    offline in under a second; the attempt limit lives only in the lock
    screen. Without a passcode the key is the constant `"no-matter-key"`.
  - **Upstream drift.** The Mac stores only an empty `.plaintextPassword`
    marker and keeps it alive through `packages/PasscodeAccessChallenge`,
    which stops the core from migrating it. If upstream drops the legacy
    cases, the Mac lock breaks.
- Move the existing Touch ID option (today a UI-only `useTouchId` setting)
  onto PasscodeCore's Keychain-backed biometrics, and add it to cold start.
- Existing users with a passcode keep it: the first unlock after the
  update moves it into PasscodeCore.
- **New dependency, stated plainly:** the database key now depends on a
  login-keychain item. If that item is lost (keychain reset, new Mac,
  copied container), local data cannot be unlocked; the app offers
  "Log out and reset" instead of a dead end. Chats reload from the
  server; secret chats are lost, as with any logout.

## Context (from discovery)
- Mac passcode code:
  - `submodules/BuildConfig/Sources/BuildConfig.m` / `BuildConfig.h`:
    `AppEncryptionParameters` (`applyPasscode`, `change`, `remove`,
    `decrypt`, `hasPasscode`), `DeviceSpecificEncryptionParameters` (DB
    key + salt). **`initWithPath` writes a new random key file when
    `.tempkeyEncrypted` is missing** (`initializeIfNeeded`, :108-147).
  - `.tempkeyEncrypted` lives in each build's data folder
    (`containerUrl` = `<group>/debug/` or `<group>/stable/`).
  - `AppEncryptionParameters` users: `Telegram-Mac/AppDelegate.swift:602,
    :643` (launch, cold-start logout), `PasscodeLockController.swift:399`
    (runtime lock), `PasscodeControllers.swift:193, :248` (change /
    disable), `PrivacyAndSecurityViewController.swift:566`
    (`hasPasscode`), `SharedAccountContext.swift:113-120`,
    `SharedNotificationManager.swift:112, :236-242` (`logout()` →
    `remove()`), `TelegramShare/ShareViewController.swift:89`.
  - `storeAccessChallengeData` callers: `PasscodeControllers.swift:183,
    :239, :259`, `SharedNotificationManager.swift:240`,
    `AppDelegate.swift:790-805` (clears a legacy non-empty marker).
  - Lock screens: `Telegram-Mac/ColdStartPasslockController.swift`
    (launch, `AppDelegate.swift:629`; no Touch ID today),
    `Telegram-Mac/PasscodeLockController.swift` (runtime auto-lock, has
    Touch ID :355-415). Settings:
    `PasscodeSettingsViewController.swift` (`useTouchId` :24, :98, :133).
  - Share extension: `TelegramShare/ShareViewController.swift:60`
    (account manager, `isReadOnly: true`), `SEPasslockController.swift`.
- Upstream `submodules/telegram-ios/submodules/PasscodeCore`:
  - `Package.swift` supports macOS; products `PasscodeCore` and
    `PasscodeAccountManager`.
  - **On macOS it uses the file-based login keychain**: no
    `kSecAttrAccessGroup` (`Passcode.swift:119-130`); service
    `org.telegram.passcode.v1` or `org.telegram.scoped.<scope>/…`. No
    `keychain-access-groups` entitlement is needed (it is restricted on
    macOS and would kill the app without a provisioning profile).
  - `configure` needs a `privateAccessGroup` closure for `.mainApp`
    (:54); biometrics need `biometricKeychainService` (:79-87) and are
    refused for `.appExtension` (:82).
  - `migrateLegacy` (:437-449) keeps `protectionEnabled = false` and the
    `unprotectedKey`, i.e. the iOS lock-only model.
  - The access key stays the same across set / change / disable
    (`updatePasscode` :567-584, `disablePasscode` :619-650); only
    `resetCredential` (:329-339) replaces it.
  - `setupAccountManager` requires a `resetLocalSecrets` closure in the
    main app (`AccountManagerIntegration.swift:68`) and calls it on a
    fresh installation.
  - `withDerivedKey` needs a `.resource(namespace:)` scope and
    `PasscodeSession.setApplicationAvailable(true)`; `.standard` sessions
    expire after 300 s. `PasscodeCrypto` is internal.
  - `PasscodeCredentialStore` storage is internal: tests outside the
    module can only use `.shared` and the real keychain.

## Development Approach
- **testing approach**: Regular (code first, then tests in the same task)
- complete each task fully before moving to the next
- small, focused commits; plain commit messages, no prefixes
- every task adds or updates tests for its code; all tests pass before
  the next task; update this plan when scope changes
- **Never lose access to data.** Any step that rewrites key material
  writes the new form first, verifies it, and only then retires the old
  one; a crash in between must leave a state the next launch can unlock.
- **Every intermediate build must work.** Tasks are cut so that no task
  leaves a reader or writer on the old scheme while the core uses the new.

## Testing Strategy
- **unit tests**:
  - `cd packages/MacPasscode && swift test` (new package; logic tested
    with fakes injected for the credential store, file I/O and the legacy
    decrypt, never the real keychain)
  - `cd packages/ApiCredentials && swift test`
  - `cd packages/PasscodeAccessChallenge && swift test` until removed
- **build check**: `xcodebuild -workspace Telegram-Mac.xcworkspace -scheme
  Telegram -configuration Debug -destination 'platform=macOS,arch=arm64'
  -derivedDataPath ~/build/TelegramSwift build`
- Real-keychain behaviour is checked in the Task 1 spike and in
  Post-Completion, not in unit tests.
- **e2e**: none in the project.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Solution Overview
- **Spike first (Task 1)** on the questions that matter for the macOS
  file keychain. If any answer is "no", **stop**: mark Task 1 ⚠️ with
  what failed and the options, and do not start Task 2.
- **Credential and protection.** `PasscodeCredentialStore` holds the
  passcode. When a passcode is set, protection is enabled
  (`protectionEnabled = true`), so the access key is reachable only
  through `verify`. After `migrateLegacy`, the app immediately calls
  `verify(code, scope: .managePasscode)` and
  `setProtectionEnabled(true, session:)`, so migrated and new passcodes
  are protected the same way. "Has passcode" is
  `protectionSettings().enabled`.
- **Database key.** The DB key (`DeviceSpecificEncryptionParameters`) is
  sealed with CryptoKit `AES.GCM` under a key from
  `withDerivedKey(namespace: "telex.db", domain: …)`, using a session
  from `verify(…, scope: .resource(namespace: "telex.db"))` or
  `unprotectedSession(namespace: "telex.db")`. Because the access key is
  stable across set / change / disable, the sealed file is written once
  and only rewritten after `resetCredential`.
- **Reset.** One `resetLocalSecrets` closure, used by
  `setupAccountManager` (fresh install), both logout paths and the
  "lost credential" recovery: `resetCredential { delete db-key.v2 and the
  legacy file; delete account databases }`.
- **Account manager.** Main app and Share extension open it with
  `setupAccountManager` (extension: `isReadOnly: true`, as today). All
  writes of the passcode state go through
  `setAccessChallengeData(accessChallengeData(reference:))` or `.none`.
- **Legacy data.** A side-effect-free legacy reader (check the file
  exists, then decrypt; never create) replaces every
  `AppEncryptionParameters` use. After migration the legacy file is
  overwritten with 64 bytes that fail to decrypt rather than deleted, so
  an older build shows its lock instead of generating a new key and
  destroying the database.
- **Legacy markers.** On account-manager init the core resolver sees the
  stored marker: `.plaintextPassword("")` → `migrateLegacy("")` throws
  `invalidCode` (harmless, but it creates Keychain items early); a
  non-empty legacy value would be migrated by the core with a kind
  guessed from length. The plan handles both explicitly (Task 3).
- **Keychain scope per build.** `keychainScope` =
  `com.korthane.telex.debug` / `com.korthane.telex.stable`, so Debug and
  Release keep separate passcodes (matching their separate data) and
  never collide with another Telegram build's unscoped items.
- **Testable glue** lives in `packages/MacPasscode`: kind mapping,
  sealed DB key file, migration and launch decisions behind injected
  closures.

## Technical Details
- `packages/MacPasscode`:
  - `PasscodeKindMapping`: apply `PasscodeKind.normalize`, then 4 / 6
    ASCII digits → `.digits4` / `.digits6`, else `.alphanumeric`.
  - `DatabaseKeyFile`: `db-key.v2` in the build's data folder; format =
    version byte + `AES.GCM` sealed box, associated data =
    `"telex.db-key.v2"`; atomic write; unknown version or failed open →
    error, never a new key.
  - `LegacyKeyReader`: wraps the old decrypt (needs a test dependency on
    `submodules/BuildConfig`, or a pure-Swift port of its AES + SHA-512
    format; the task picks one and records it).
  - `LaunchUnlock`: decides among `v2` / `legacy` / `fresh` /
    `credentialLost` from injected file checks and store answers.
- Launch (`AppDelegate.unlockAndLaunch`):
  1. `PasscodeEnvironment.shared.configure(appGroup, .mainApp,
     biometricKeychainService:, keychainScope:, privateAccessGroup:)`;
     `PasscodeSession.setApplicationAvailable(true)`.
  2. `db-key.v2` exists: no protection → `unprotectedSession`, unseal;
     protection → `ColdStartPasslockController` with `verify` (or Touch
     ID), unseal right away (sessions expire).
  3. Only the legacy file exists: unlock as today with the legacy reader;
     then migrate: `migrateLegacy(code, mappedKind)` → `verify` →
     `setProtectionEnabled(true)` (if a code was set) → seal and write
     `db-key.v2` → unseal to verify → store `.secured` → poison the
     legacy file. Each step is resumable.
  4. Neither: fresh install → new DB key, sealed under the unprotected
     session.
  5. Store throws `.unavailable` / `.corrupted` / `.keychain`: show an
     error with "Log out and reset" (calls the reset closure).
- Errors on lock screens: `.cooldown(seconds)` shows the wait,
  `.invalidCode` shakes.

## What Goes Where
- **Implementation Steps**: code, tests, docs.
- **Post-Completion**: manual checks with signed builds and real data.

## Implementation Steps

### Task 1: Spike: PasscodeCore on the macOS login keychain
**Files:**
- Modify: `Telegram.xcodeproj/project.pbxproj` (link PasscodeCore products)
- Create: a temporary debug-only check (launch argument), removed at the end

- [ ] add `submodules/telegram-ios/submodules/PasscodeCore` as a local
      package; link `PasscodeCore` + `PasscodeAccountManager` to the app
      and TelegramShare; Debug build passes
- [ ] (a) app creates a test credential (`configure` + `setPasscode`);
      TelegramShare reads it with `verify` without a keychain access
      prompt or `errSecInteractionNotAllowed`
- [ ] (b) a wrong code in TelegramShare writes the `attempts` item and the
      cooldown is visible to the app afterwards
- [ ] (c) rebuilding Debug (new binary, same signing) still reads the
      item without prompts; note behaviour for ad-hoc signed configs
- [ ] (d) `enableBiometrics` + `authenticateBiometrics` work on the file
      keychain (`.biometryCurrentSet`), or fail cleanly with
      `biometricsUnavailable`
- [ ] (e) a second `keychainScope` does not see the first scope's items
- [ ] record (a)–(e) in this plan; on any failure mark this task ⚠️,
      list the options, remove the temporary code and STOP
- [ ] remove the temporary check (keep the package link); clean up the
      test credential with `resetCredential`; run the build check

### Task 2: MacPasscode package
**Files:**
- Create: `packages/MacPasscode/Package.swift`
- Create: `packages/MacPasscode/Sources/MacPasscode/{PasscodeKindMapping,DatabaseKeyFile,LegacyKeyReader,LaunchUnlock}.swift`
- Create: `packages/MacPasscode/Tests/MacPasscodeTests/*`

- [ ] kind mapping with `normalize` and the ASCII-digit check
- [ ] `DatabaseKeyFile` seal / unseal / atomic write / version check
- [ ] `LegacyKeyReader`: read-only decrypt of `.tempkeyEncrypted`, never
      creates a file; `poison()` overwrites it with undecryptable bytes
- [ ] `LaunchUnlock` decision (v2, legacy, fresh, credential lost) and
      the resumable migration steps, against injected fakes
- [ ] tests: mapping (incl. non-ASCII digits); seal round trip, wrong
      key, truncated file, unknown version; legacy reader on a missing
      file creates nothing; migration interrupted after each step resumes
      correctly; protection is enabled after migrating a set passcode;
      wrong code changes nothing
- [ ] run `swift test`

### Task 3: Switch the main app to PasscodeCore (launch, lock screens, settings, logout)
One task so no intermediate build mixes the schemes.

**Files:**
- Modify: `Telegram-Mac/AppDelegate.swift`
- Modify: `Telegram-Mac/ColdStartPasslockController.swift`
- Modify: `Telegram-Mac/PasscodeLockController.swift`
- Modify: `Telegram-Mac/PasscodeControllers.swift`
- Modify: `Telegram-Mac/PasscodeSettingsViewController.swift`
- Modify: `Telegram-Mac/PrivacyAndSecurityViewController.swift`
- Modify: `Telegram-Mac/SharedAccountContext.swift`
- Modify: `Telegram-Mac/SharedNotificationManager.swift`

- [ ] configure `PasscodeEnvironment` (scope, biometric service, private
      group closure) and `setApplicationAvailable(true)` at launch; open
      the account manager with `setupAccountManager` and the reset closure
- [ ] launch flow from Technical Details via `LaunchUnlock`, including
      migration and the "credential lost → Log out and reset" screen
- [ ] handle stored legacy markers: empty → no-op; non-empty → migrate
      with the plan's kind mapping before the core can guess
- [ ] cold-start and runtime lock: `verify` (`.resource` / `.appUnlock`),
      cooldown seconds, shake on wrong code
- [ ] settings set / change / disable through `PasscodeCredentialStore`
      (`setPasscode`, `setPasscodeWithSettingsSession`, `disablePasscode`)
      and `setAccessChallengeData`; `hasPasscode` from
      `protectionSettings()`; drop the marker cleanup at `:790-805`
- [ ] both logout paths (`SharedNotificationManager.logout()`, cold-start
      `logoutImpl`) call the reset closure; no second `.passthrough`
      account manager
- [ ] replace every remaining `AppEncryptionParameters` use in the app
      with `LegacyKeyReader` or PasscodeCore
- [ ] tests for any new MacPasscode helper this task needs; run all unit
      tests and the build check

### Task 4: Touch ID on PasscodeCore
Only if Task 1 (d) passed; otherwise mark ⚠️ and keep the existing
UI-only Touch ID unchanged.

**Files:**
- Modify: `Telegram-Mac/PasscodeSettingsViewController.swift`
- Modify: `Telegram-Mac/PasscodeLockController.swift`
- Modify: `Telegram-Mac/ColdStartPasslockController.swift`

- [ ] the existing `useTouchId` toggle calls `enableBiometrics` /
      `disableBiometrics`; carry over users with `useTouchId = true`
      (enable at their next passcode unlock)
- [ ] cold-start and runtime lock offer Touch ID first via
      `authenticateBiometrics`, fall back to the code
- [ ] tests for helper logic (toggle visibility, carry-over decision)
- [ ] run all unit tests and the build check

### Task 5: Share extension unlock
**Files:**
- Modify: `TelegramShare/ShareViewController.swift`
- Modify: `TelegramShare/SEPasslockController.swift`

- [ ] configure `PasscodeEnvironment` with `.appExtension` and the same
      scope; account manager via `setupAccountManager` (`isReadOnly: true`)
- [ ] unlock with `verify` and unseal `db-key.v2`; never migrate, write
      key material or reset from the extension; no Touch ID (refused for
      extensions by design)
- [ ] only the legacy file present → "Open Telex once to finish the
      update"
- [ ] tests for the extension's decision helper (wrong code, legacy-only,
      credential lost); run all unit tests and the build check

### Task 6: Remove the old storage and the adapter
**Files:**
- Delete: `packages/PasscodeAccessChallenge`
- Modify: `submodules/BuildConfig/Sources/BuildConfig.m`, `BuildConfig.h`
- Modify: `Telegram.xcodeproj/project.pbxproj`

- [ ] delete the adapter package and its tests
- [ ] remove `AppEncryptionParameters` (or keep only what
      `LegacyKeyReader` needs), plus the unused `encryptData` /
      `decryptData` and the old `.tempkey` upgrade; record whether
      `.tempkey`-only installs are still supported
- [ ] `git grep` finds no remaining users
- [ ] run all unit tests and the build check

### Task 7: Verify acceptance criteria
- [ ] fresh install: launch works, `db-key.v2` exists, no legacy file
- [ ] legacy install with and without a passcode (fixture built by the
      old code path in a test): first unlock migrates, protection is on
      when a code was set, the legacy file is poisoned
- [ ] all unit tests and the build check pass
- [ ] launch the Debug build once from the terminal and quit it (do not
      kill processes you did not start)

### Task 8: [Final] Update documentation
- [ ] INSTALL.md: passcode in PasscodeCore / login keychain; data depends
      on that keychain item ("Log out and reset" if lost); Touch ID; Share
      extension needs Telex opened once after the update; downgrading
      after the update cannot open local data; update the test-command
      lines that mention PasscodeAccessChallenge
- [ ] remove the passcode item from `nogit_todo.md`
- [ ] update CLAUDE.md if a non-obvious rule came up
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion
*Manual, with signed builds and real data*

**Before running the new build** back up the app group folder
(`~/Library/Group Containers/<TeamID>.com.korthane.telex/`): migration
rewrites the database key file.

**Manual checks:**
- Old build with a passcode → update → unlock once → quit → start again:
  same code unlocks; Keychain Access shows the scoped items.
- Old build without a passcode → update: launches without a prompt.
- Wrong codes: cooldown appears and survives a restart.
- Set, change and disable the passcode; restart after each.
- Touch ID: enable, lock, unlock; cancel falls back to the code.
- Share extension with a passcode set; and before the main app has run
  once after the update.
- Delete the scoped Keychain items by hand → "Log out and reset" appears
  and works.
- Log out from the lock screen; next launch starts clean.
- Debug and Release: a passcode in one does not lock the other.
- Sandboxed Release build: all of the above.
