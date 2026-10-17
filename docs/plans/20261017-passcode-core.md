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
    `org.telegram.passcode.v1` or `org.telegram.scoped.<scope>/…`. The
    Task 1 spike showed the login keychain cannot be shared between the
    app and TelegramShare (`errSecAuthFailed`), so the plan switches to
    the data protection keychain with a `keychain-access-groups`
    entitlement (restricted on macOS: needs provisioning profiles, Task 2)
    and a small PasscodeCore patch (Task 3).
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
  -derivedDataPath ~/build/TelegramSwift -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration build` (the provisioning flags
  are required since Task 2)
- Real-keychain behaviour is checked in the Task 1 spike and in
  Post-Completion, not in unit tests.
- **e2e**: none in the project.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Solution Overview
- **Spike first (Task 1, done: failed on the login keychain).** Then
  provisioning profiles + a shared keychain access group (Task 2), a
  PasscodeCore patch to use it on macOS (Task 3), and the same checks
  again (Task 4). Tasks 2 and 4 STOP the run on failure.
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

### Task 1: Spike: PasscodeCore on the macOS login keychain ⚠️ FAILED
**Files:**
- Modify: `Telegram.xcodeproj/project.pbxproj` (link PasscodeCore products)
- Create: a temporary debug-only check (launch argument), removed at the end

- [x] add `submodules/telegram-ios/submodules/PasscodeCore` as a local
      package; link `PasscodeCore` + `PasscodeAccountManager` to the app
      and TelegramShare; Debug build passes
- [x] (a) app creates a test credential (`configure` + `setPasscode`);
      TelegramShare reads it with `verify` without a keychain access
      prompt or `errSecInteractionNotAllowed` ⚠️ FAILED: `errSecAuthFailed`
- [x] (b) a wrong code in TelegramShare writes the `attempts` item and the
      cooldown is visible to the app afterwards ⚠️ FAILED: never reached
- [x] (c) rebuilding Debug (new binary, same signing) still reads the
      item without prompts; note behaviour for ad-hoc signed configs
- [x] (d) `enableBiometrics` + `authenticateBiometrics` work on the file
      keychain (`.biometryCurrentSet`), or fail cleanly with
      `biometricsUnavailable` (fails cleanly)
- [x] (e) a second `keychainScope` does not see the first scope's items
- [x] record (a)–(e) in this plan; on any failure mark this task ⚠️,
      list the options, remove the temporary code and STOP
- [x] remove the temporary check (keep the package link); clean up the
      test credential with `resetCredential`; run the build check

**Spike results** (2026-10-17, macOS 27.0.1, login keychain). The check
ran as a harness outside the repo, not as a launch argument: a SwiftPM
tool on PasscodeCore, signed twice with the Debug identity (Apple
Development: Oleh Lomaka, team 2FKX9S8MFA) as bundles with the app's and
the extension's identifiers and entitlements (the extension copy
sandboxed), so both designated requirements equal the real ones. Keychain
UI was disabled (`SecKeychainSetUserInteractionAllowed(false)`), so a
would-be prompt shows up as an error. Scope `com.korthane.telex.spike`.
- (a) **Fails.** App harness: `setPasscode` OK, items
  `org.telegram.scoped.com.korthane.telex.spike/org.telegram.passcode.v1`
  `#credential` and `#device`. Extension harness: `hasStoredCredential`,
  `protectionSettings` and `verify` all throw `keychain(-25293)`
  (`errSecAuthFailed`); same without the sandbox. `security dump-keychain
  -a` shows why: `decrypt` is allowed for one application, requirement
  `identifier "com.korthane.telex" …`; partition `teamid:2FKX9S8MFA` does
  not widen it. With UI allowed this would be an access prompt. Not run
  in the real Share extension (needs a share from another app); the
  harness has the same code requirement, which is what the ACL checks.
- (b) **Fails.** A wrong code in the extension stops at the same
  `keychain(-25293)` before `attempts` is written. Raw probe: an item the
  extension creates is unreadable by the app (`-25293`); the app can
  still overwrite it (`SecItemUpdate` = 0; `encrypt` is open to all).
- (c) **Passes for team-signed builds.** Five rebuilds with new cdhashes
  and a copy to another path read the credential, verify, and delete
  `attempts` with status 0. Ad-hoc signing (designated requirement =
  cdhash): after a rebuild `verify` throws `keychain(-25293)`, i.e. every
  ad-hoc rebuild would lose the credential (target configs are all
  "Apple Development"; only project-level defaults are `-`). Items made
  by a bare, non-bundle tool could not be deleted by the bundle build
  (`-25244`, `errSecInvalidOwnerEdit`); irrelevant for the app bundle.
- (d) **Fails cleanly.** Touch ID present (`canEvaluatePolicy` true).
  `enableBiometrics` → `biometricsUnavailable`; raw `SecItemAdd` with
  `.biometryCurrentSet` access control returns `-34018`
  (`errSecMissingEntitlement`), which PasscodeCore maps to
  `biometricsUnavailable`; `authenticateBiometrics` → same.
- (e) **Passes.** Scope `com.korthane.telex.spike2`: no credential, no
  items listed, `verify` → `authenticationRequired`.
- Other probes: data protection keychain with the app group as access
  group: `SecItemAdd` = `-34018` in both binaries (needs a provisioning
  profile). An item added with an explicit `SecAccess` trusting both
  binaries (`SecTrustedApplicationCreateFromPath`): extension read 0,
  extension update 0, app read afterwards 0, no prompt.
- Cleanup: all spike items deleted (`security dump-keychain | grep -c
  com.korthane.telex.spike` → 0). Debug build passes with the package
  linked; `ApiCredentials` tests pass (25).

**Options** (decided 2026-10-17: option 3, see Task 2):
1. Patch PasscodeCore's macOS write path to add items with a `SecAccess`
   trusting the app and the embedded `TelegramShare.appex` (probe above
   works). Costs: a change in upstream code, deprecated legacy APIs, the
   `attempts` item needs it too, and ACLs follow the code requirement, so
   Debug/Release and ad-hoc builds still differ.
2. Keep the extension away from the keychain: with a passcode set it
   asks to open Telex instead of unlocking itself. Smallest change; the
   Share sheet loses passcode unlock.
3. Use the data protection keychain with the app group as access group.
   Needs provisioning profiles for Debug and Developer ID builds; also
   enables `.biometryCurrentSet` items (d).
4. Leave PasscodeCore and fix the file scheme instead (salted slow KDF,
   attempts outside the lock screen), without the keychain binding.

### Task 2: Signing with provisioning profiles and a shared keychain group
Decision 2026-10-17 (after the Task 1 spike): use the data protection
keychain shared through a keychain access group, which needs provisioning
profiles. The user creates the profiles; this task wires the project.

**Files:**
- Modify: `Telegram.xcodeproj/project.pbxproj`
- Modify: `Telegram-Mac/Telegram-Mac.entitlements`, `Telegram-Mac/Telegram-Sandbox.entitlements`, `TelegramShare/TelegramShare.entitlements`
- Modify: `Telegram-Mac/Secrets.xcconfig.example` (or the template the project uses), `INSTALL.md`

- [x] add `keychain-access-groups` =
      `$(AppIdentifierPrefix)com.korthane.telex.shared` to the app (Debug
      and Sandbox) and TelegramShare entitlements
- [x] Debug: automatic signing creates the development profiles; document
      `-allowProvisioningUpdates` for command-line builds and update the
      plan's build check accordingly
- [x] Release: profile names (Developer ID) come from `Secrets.xcconfig`
      (e.g. `TELEX_APP_PROFILE`, `TELEX_SHARE_PROFILE`), never committed
- [x] INSTALL.md: what each builder must register (App IDs
      `com.korthane.telex` and `com.korthane.telex.TelegramShare` with App
      Groups + Keychain Sharing; development and Developer ID profiles)
- [x] ⚠️ manual: the user creates the App IDs and profiles; if the Debug
      build cannot be signed yet, mark this checkbox ⚠️ with the exact
      signing error and STOP (do not start Task 3)
- [x] Debug build check passes with the new entitlement; `codesign -d
      --entitlements -` shows the group on Telex.app and TelegramShare.appex

**Results** (2026-10-17). The user registered both App IDs (App Groups
only) in team 2FKX9S8MFA. The first build with `-allowProvisioningUpdates`
failed with `Device "descartes" isn't registered in your developer
account.` and `No profiles for 'com.korthane.telex' were found`; adding
`-allowProvisioningDeviceRegistration` registered the Mac and created:
- `Mac Team Provisioning Profile: com.korthane.telex`
  (`8b06bbaf-6466-4814-8c2a-41a462297692`)
- `Mac Team Provisioning Profile: com.korthane.telex.TelegramShare`
  (`9181306c-8c04-4aa2-bc92-47fcb8b23e69`)

Both profiles allow `keychain-access-groups` = `2FKX9S8MFA.*`, so the
Keychain Sharing capability is not needed. Telex.app and
TelegramShare.appex each carry `embedded.provisionprofile`; signed
entitlements show `keychain-access-groups` =
`2FKX9S8MFA.com.korthane.telex.shared`; `codesign --verify --deep
--strict` passes. The Debug binary ran 8 s and quit normally (not
killed by AMFI). Release reads `TELEX_RELEASE_SIGN_STYLE`,
`TELEX_RELEASE_SIGN_IDENTITY`, `TELEX_APP_PROFILE`,
`TELEX_SHARE_PROFILE` from `Secrets.xcconfig` (defaults: Automatic,
Apple Development, no profile); checked with `-showBuildSettings`, not
signed with Developer ID yet (no profiles exist).

### Task 3: Patch PasscodeCore to use the shared group on macOS
**Files:**
- Create: `patches/telegram-ios/passcodecore-macos-access-group.patch`
- Modify: whatever applies `patches/telegram-ios/` (same mechanism as the
  existing patches there)

- [x] on macOS, add `kSecUseDataProtectionKeychain: true` and the access
      group to `PasscodeKeychain.query` (today `#if !os(macOS)`,
      `Passcode.swift:126`); use `sharedAccessGroup()` /
      `privateAccessGroup()` as on iOS
- [x] the app passes the group to `PasscodeEnvironment.configure` (shared
      group; private group = the app's own `$(AppIdentifierPrefix)` +
      bundle ID) (deferred to Task 6: no app code calls `configure` yet;
      values and entitlement prepared, see results)
- [x] keep the patch minimal and documented in its header (why, which
      upstream lines)
- [x] the patch applies cleanly from a fresh checkout; Debug build passes

**Results** (2026-10-17).
- `patches/telegram-ios/passcodecore-macos-access-group.patch` is picked
  up by the existing loop in `scripts/configure_frameworks.sh`
  (`patches/*/*.patch`); no script change needed. It applies on a fresh
  index of the pinned commit `f1dd7a2d` together with the other five
  telegram-ios patches.
- `PasscodeKeychain.query` is the only query PasscodeCore's storage uses
  (read, write incl. the `.biometryCurrentSet` item, remove), so one
  change moves all of it to the data protection keychain. Left alone and
  noted in the header: `adoptGroupedItem` (now a no-op repeat; runs only
  without a `keychainScope`) and `PasscodeKeychainScope.migrateLegacyItems`
  (still copies within the login keychain; Telex must not call it).
- Group values, read from the code: `sharedAccessGroup()` returns
  `PasscodeConfiguration.appGroupIdentifier` verbatim (macOS only checks
  it contains a dot), and `privateAccessGroup()` returns the closure's
  value unchecked on macOS. So Task 6 configures
  `appGroupIdentifier: "<prefix>com.korthane.telex.shared"` (the keychain
  group, not the app group) and `privateAccessGroup: {
  "<prefix>com.korthane.telex" }`. The prefix differs per builder, so
  Task 6 reads it at runtime (e.g. an Info.plist key set to
  `$(AppIdentifierPrefix)`) rather than hard-coding `2FKX9S8MFA.`.
- The app entitlements (Debug and Sandbox, not TelegramShare) now also list
  `$(AppIdentifierPrefix)com.korthane.telex` after the shared group (the
  first entry stays the default group). Signed Telex.app shows
  `keychain-access-groups` = `2FKX9S8MFA.com.korthane.telex.shared`,
  `2FKX9S8MFA.com.korthane.telex`; TelegramShare.appex only the shared
  one; `codesign --verify --deep --strict` passes.
- PasscodeCore `swift test`: 30 tests, 0 failures, 2 skipped. The two
  round trips through the real keychain need the entitlement, which an
  unsigned test binary lacks (`-34018`), so the patch makes them skip
  and checks the query attributes instead; Task 4 covers the real
  keychain. `ApiCredentials` 25 and `PasscodeAccessChallenge` 6 pass;
  Debug build check passes.

### Task 4: Re-run the keychain checks on the shared group
- [x] repeat Task 1 (a)–(e) with the real signing and the patched
      PasscodeCore (same harness approach, test scope
      `com.korthane.telex.spike`, cleaned up afterwards) (a), (b), (c),
      (e) pass; (d) ⚠️ partially verified: item creation works, the
      fingerprint step is left for the user
- [x] record results under this task; any failure → mark ⚠️ with the
      options and STOP (no failure)

**Results** (2026-10-17, macOS 27.0.1, data protection keychain). Same
harness as Task 1 (SwiftPM tool outside the repo, on the patched
PasscodeCore), now built as two `.app` bundles signed exactly like the
Debug targets: bundle IDs `com.korthane.telex` and
`com.korthane.telex.TelegramShare`, the signed entitlements copied from
the built Telex.app / TelegramShare.appex (incl. `keychain-access-groups`,
extension sandboxed), the Xcode-managed development profiles embedded
(`8b06bbaf-…`, `9181306c-…`), Apple Development identity, hardened
runtime. Neither was killed by AMFI. Configured as Task 6 will:
`appGroupIdentifier: "2FKX9S8MFA.com.korthane.telex.shared"`, app role
with `privateAccessGroup: { "2FKX9S8MFA.com.korthane.telex" }` and
`biometricKeychainService: "telex.biometric"`, extension role with
neither; scope `com.korthane.telex.spike`; legacy keychain UI disabled.
- (a) **Passes.** App `setPasscode` creates
  `org.telegram.scoped.com.korthane.telex.spike/org.telegram.passcode.v1`
  `#credential` and `#device` in group `…telex.shared`. Extension:
  lists both (status 0), `hasStoredCredential` true,
  `protectionSettings` enabled, `verify` OK (32-byte derived key), no
  prompt, no error.
- (b) **Passes.** Six wrong codes in the extension → `invalidCode` each
  and an `#attempts` item in `…telex.shared`. The app then reads
  `cooldownRemaining` 60 and `verify` with the right code throws
  `cooldown(60)`; the extension sees the same cooldown (53 s left).
  After it expired, a correct `verify` from a rebuilt extension deleted
  `#attempts`.
- (c) **Passes.** Two rebuilds (new cdhashes each, app and extension) and
  a copy of the third to another directory: all read the credential and
  verify with status 0; a wrong code from the moved app writes
  `#attempts`, a later correct code from another build clears it. An
  ad-hoc signed copy with the same entitlements is killed at launch
  (exit 137, SIGKILL by AMFI): restricted entitlements need the team
  signature plus profile, so ad-hoc builds cannot run at all.
- (d) **⚠️ Partially verified.** Touch ID present (`canEvaluatePolicy`
  true). `enableBiometrics` (non-interactive `LAContext`) now gets past
  the item creation that failed with `-34018` in Task 1: PasscodeCore's
  `.biometryCurrentSet` `SecItemAdd` succeeds, and its read-back stops at
  the biometric gate with `keychain(-25308)` (`errSecInteractionNotAllowed`
  = the Touch ID prompt would appear); PasscodeCore then rolls the item
  back, so `biometricsEnabled` stays false and `authenticateBiometrics`
  returns `biometricsUnavailable` without reaching a prompt. Raw probe
  with the same attributes: add 0, read without UI `-25308`,
  attributes-only read 0, delete 0, in both groups. Extension role:
  `enableBiometrics` → `unavailable` (no biometric service, by design).
  **Left for the user:** enable Touch ID and unlock with a finger once
  Task 7 wires it, to confirm the read-back and `authenticateBiometrics`.
- (e) **Passes.** Scope `com.korthane.telex.spike2` in both roles: no
  credential, `verify` → `authenticationRequired`; a passcode set there
  gets its own `…spike2/…` items and does not touch the first scope's.
- **Finding for Task 6/7:** the "private" group
  `2FKX9S8MFA.com.korthane.telex` is also the app group ID, and on macOS
  `com.apple.security.application-groups` grants keychain access to that
  group: the extension read an item the app put there (status 0), while
  a group in neither entitlement gives `-34018`. So the biometric item
  would not be app-only. Use a distinct private group instead (e.g.
  `$(AppIdentifierPrefix)com.korthane.telex.private`, app entitlements
  only; the profiles allow `2FKX9S8MFA.*`).
- Cleanup: `resetCredential` for both scopes (it rewrites `#device` and
  `#credential` as an unprotected record), then all `.spike` items
  deleted (status 0). A data-protection `SecItemCopyMatching` from both
  harnesses returns `-25300` (none left); login keychain has no
  `.spike` items. Real Telex items and the running Telex were not
  touched.

### Task 5: MacPasscode package
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

### Task 6: Switch the main app to PasscodeCore (launch, lock screens, settings, logout)
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

### Task 7: Touch ID on PasscodeCore
Only if Task 4 (d) passed; otherwise mark ⚠️ and keep the existing
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

### Task 8: Share extension unlock
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

### Task 9: Remove the old storage and the adapter
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

### Task 10: Verify acceptance criteria
- [ ] fresh install: launch works, `db-key.v2` exists, no legacy file
- [ ] legacy install with and without a passcode (fixture built by the
      old code path in a test): first unlock migrates, protection is on
      when a code was set, the legacy file is poisoned
- [ ] all unit tests and the build check pass
- [ ] launch the Debug build once from the terminal and quit it (do not
      kill processes you did not start)

### Task 11: [Final] Update documentation
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
