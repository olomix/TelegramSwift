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
- **Account manager.** Main app and Share extension build their own
  `AccountManagerAccessChallenge` instead of `setupAccountManager`, whose
  resolver migrates legacy markers (Task 6). The app uses the core's
  resolver minus that migration; the extension (`isReadOnly: true`, as
  today) keeps the stored state as is (Task 8). All writes of the passcode
  state go through `setAccessChallengeData(accessChallengeData(reference:))`
  or `.none`.
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
- Create: `packages/MacPasscode/Sources/MacPasscode/{PasscodeKindMapping,DatabaseKeyFile,LegacyKeyReader,LaunchUnlock,KeyFileStorage}.swift`
- Create: `packages/MacPasscode/Tests/MacPasscodeTests/*`

- [x] kind mapping with `normalize` and the ASCII-digit check
- [x] `DatabaseKeyFile` seal / unseal / atomic write / version check
- [x] `LegacyKeyReader`: read-only decrypt of `.tempkeyEncrypted`, never
      creates a file; `poison()` (named `retire()`) overwrites it with undecryptable bytes
- [x] `LaunchUnlock` decision (v2, legacy, fresh, credential lost) and
      the resumable migration steps, against injected fakes
- [x] tests: mapping (incl. non-ASCII digits); seal round trip, wrong
      key, truncated file, unknown version; legacy reader on a missing
      file creates nothing; migration interrupted after each step resumes
      correctly; protection is enabled after migrating a set passcode;
      wrong code changes nothing
- [x] run `swift test`

**Results** (2026-10-17).
- `LegacyKeyReader` is a pure-Swift port (CommonCrypto AES-256-CBC
  without padding, CryptoKit SHA-512, murmur3-32 with the
  `MurMurHash32.m` seed), so Task 9 can delete `AppEncryptionParameters`
  outright. Checked against the ObjC code with a scratchpad harness that
  links `submodules/BuildConfig`: 300 random cases (no passcode, digits,
  Arabic-Indic, Devanagari, fullwidth, emoji, umlauts) written by
  `AppEncryptionParameters` read back identically, wrong codes rejected,
  retired files opened by neither the default key nor the old code.
  Five files the old code wrote are committed as hex fixtures; the test
  encrypt helper reproduces them byte for byte.
- `.tempkey`-only installs stay supported: a 48-byte `.tempkey` is read
  as an unprotected key and wins over `.tempkeyEncrypted`, as the old
  init did; `retire()` removes it after poisoning.
- `retire()` writes a 64-byte marker (`telex.legacy-key.retired` + random)
  so the reader tells "migrated" from "has a passcode"; the old code
  sees a file it cannot open and shows its lock screen.
- A live legacy file always wins over `db-key.v2` in `state()`: a crash
  before `retire()` re-runs the whole idempotent migration, which
  rewrites `db-key.v2` with the same database key.
- `LaunchCredentialStore` is the seam to PasscodeCore; Task 6 implements
  it over `PasscodeCredentialStore` (`databaseSealingKey` = `verify(…,
  .resource("telex.db"))` or `unprotectedSession` + `withDerivedKey`;
  `resetCredential` must not delete files). `createFresh` resets a
  leftover protected credential, since no key file exists to lose.
- Tests: 49 (`swift test`), incl. crash after every step of migration
  (with and without a passcode) and of a fresh install; a mutation that
  retires before writing `db-key.v2` fails 38 of them.


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

- [x] configure `PasscodeEnvironment` (scope, biometric service, private
      group closure) and `setApplicationAvailable(true)` at launch; open
      the account manager with `setupAccountManager` and the reset closure
      (own `AccountManagerAccessChallenge` with the same prepare / reset /
      cleanup, see results)
- [x] launch flow from Technical Details via `LaunchUnlock`, including
      migration and the "credential lost → Log out and reset" screen
- [x] handle stored legacy markers: empty → no-op; non-empty → migrate
      with the plan's kind mapping before the core can guess
- [x] cold-start and runtime lock: `verify` (`.resource` / `.appUnlock`),
      cooldown seconds, shake on wrong code
- [x] settings set / change / disable through `PasscodeCredentialStore`
      (`setPasscode`, `setPasscodeWithSettingsSession`, `disablePasscode`)
      and `setAccessChallengeData`; `hasPasscode` from
      `protectionSettings()`; drop the marker cleanup at `:790-805`
- [x] both logout paths (`SharedNotificationManager.logout()`, cold-start
      `logoutImpl`) call the reset closure; no second `.passthrough`
      account manager
- [x] replace every remaining `AppEncryptionParameters` use in the app
      with `LegacyKeyReader` or PasscodeCore
- [x] tests for any new MacPasscode helper this task needs; run all unit
      tests and the build check

**Results** (2026-10-17).
- Glue in `Telegram-Mac/LocalPasscode.swift` (new, app target only);
  `MacPasscode` is now linked to the app. Keychain values come from
  `MacPasscodeEnvironment`: shared group `<prefix>com.korthane.telex.shared`
  (passed as `appGroupIdentifier`), private group
  `<prefix>com.korthane.telex.private` (replaces the
  `$(AppIdentifierPrefix)com.korthane.telex` entry in both app
  entitlements, see the Task 4 finding), scope
  `com.korthane.telex.<ApiEnvironment.prefix>`, biometric service
  `telex.biometric`. The prefix is read from the new Info.plist key
  `TGKeychainGroupPrefix` = `$(AppIdentifierPrefix)`; the built app shows
  `2FKX9S8MFA.`. A build without it stops with a developer alert, like
  the app group check.
- **Account manager: not `setupAccountManager`.** Its resolver would
  migrate the Mac's markers itself (`.plaintextPassword("")` →
  `migrateLegacy("")`, a non-empty code with a guessed kind) before any
  app code runs. The app builds the same `AccountManagerAccessChallenge`
  (shared-group check, `configureLock`, reset on a fresh installation,
  `resumeCleanup`) with the core's resolver minus the legacy-marker
  migration. A non-empty marker (pre-`AppEncryptionParameters` builds)
  becomes the passcode through `LaunchUnlock.unlockLegacy(code: nil,
  settingPasscode:)` when the key file has no passcode, with the plan's
  kind mapping; an empty marker is left alone and is overwritten by
  `.secured` at the end of migration.
- `CoreLaunchCredentialStore` implements `LaunchCredentialStore`.
  `setProtectionEnabled` requires a `.settings` session, so
  `enableProtection` verifies with `.settings`, not `.managePasscode` as
  Solution Overview says.
- Launch (`AppDelegate.unlockAndLaunch` → `LocalPasscode.prepareLaunch`,
  on a background queue after the account manager finished `prepare`):
  fresh → `createFresh`; no passcode → unlock directly; passcode →
  `ColdStartPasslockController` (async check, wrong code shakes, cooldown
  shows the seconds); credential lost, store or unseal errors → an alert
  with "Quit" (default, keeps every file) and "Log Out and Reset".
- Resets: `LaunchUnlock.resetLocalSecrets` deletes `db-key.v2`,
  `.tempkeyEncrypted`, `.tempkey`, then (fresh install, cold-start logout,
  error alert) the `account-*` folders, then replaces the credential.
  Cold-start logout and the alert also remove the account records from
  the open account manager instead of opening a second one. The runtime
  logout (accounts open, already logged out by `logoutFromAccount`) keeps
  the databases: reset, then `sealAfterReset` seals the running key again
  under the new unprotected credential.
- **Fresh installs and post-reset seals write a retired
  `.tempkeyEncrypted`** (`createFresh` / `sealAfterReset` call
  `retire()`). Otherwise an older build, or the not yet updated Share
  extension, would see no key file, create one with a random key, and the
  next launch would migrate that wrong key over `db-key.v2`. Task 10's
  "no legacy file" check becomes "a retired legacy file".
- Migration also recovers from a credential left by an earlier install:
  a stale passcode (`invalidCode` after `migrateLegacy`) → reset, retry;
  a reset credential (managed, no passcode) → `setPasscode(…, session:
  nil)`; a protected credential while the key file has no passcode →
  reset first. All three only while the legacy file is live and holds the
  key.
- Settings: install requires an existing credential (a new one would not
  open `db-key.v2`), then `setPasscode(…, session: nil)` with the mapped
  kind; change = `verify(.managePasscode)` + `setPasscode(…, session:)`;
  disable = `verify(.managePasscode)` + `disablePasscode`; each then
  `setAccessChallengeData`. `setPasscodeWithSettingsSession` is not
  needed until Touch ID (Task 7). `PasscodeSettingsViewController` is
  unchanged: it already treats `.secured` like the old markers.
- New English-only strings (cooldown, keychain errors, the alert), like
  the other Telex-specific alerts.
- (Resolved in Task 8.) Until Task 8 TelegramShare still used
  `AppEncryptionParameters`, so after the app migrates (legacy file
  retired) the extension shows its lock and no code opens it. It never
  writes: the retired file stops its key generation.
- Tests: MacPasscode 60 (new: marker code, stale / reset / protected
  leftover credentials, reset order and failure, `sealAfterReset`,
  retired marker on fresh install, environment values, failure mapping);
  ApiCredentials 25; PasscodeAccessChallenge 6. Debug build check passes;
  signed Telex.app has `…telex.shared` + `…telex.private`, the appex only
  `…telex.shared`; `codesign --verify --deep --strict` passes. The new
  build was not launched: the user's Telex is running and owns the data
  folder (single-instance guard), and data safety rules out a test run
  against it.

### Task 7: Touch ID on PasscodeCore
Only if Task 4 (d) passed; otherwise mark ⚠️ and keep the existing
UI-only Touch ID unchanged.

**Files:**
- Modify: `Telegram-Mac/PasscodeSettingsViewController.swift`
- Modify: `Telegram-Mac/PasscodeLockController.swift`
- Modify: `Telegram-Mac/ColdStartPasslockController.swift`

- [x] the existing `useTouchId` toggle calls `enableBiometrics` /
      `disableBiometrics`; carry over users with `useTouchId = true`
      (enable at their next passcode unlock)
- [x] cold-start and runtime lock offer Touch ID first via
      `authenticateBiometrics`, fall back to the code
- [x] tests for helper logic (toggle visibility, carry-over decision)
- [x] run all unit tests and the build check
- [x] ⚠️ manual (skipped - not automatable): a real fingerprint. The user
      must turn Touch ID on in settings, lock, and unlock with a finger at
      the runtime lock and at launch; cancel must fall back to the code

**Results** (2026-10-17). Task 4 (d) counted as passed (item creation
works); the fingerprint step is still the user's (checkbox above).
- MacPasscode (`TouchId.swift`): `TouchIdPolicy.showsToggle` (passcode on,
  and a sensor or Touch ID already on, so it can be turned off with the
  lid closed) and `offersUnlock` (passcode, Touch ID and sensor);
  `TouchIdCarryOver` runs after a passcode unlock with the code.
  `LaunchCredentialStore` gained `isBiometricsEnabled` and
  `biometricDatabaseSealingKey(context:)`; `LaunchUnlock.offersBiometrics()`
  is true only for `.v2(needsPasscode: true)` (a live legacy file needs
  the code to migrate), and `unlockV2(biometrics:)` unseals `db-key.v2`
  with a key derived from `authenticateBiometrics(…, .resource("telex.db"))`,
  the same namespace and domain as a passcode unlock, right away.
- Settings: the row reads `protectionSettings()` (`biometricsEnabled`),
  refreshed on the store's `changes`, not `AdditionalSettings.useTouchId`.
  Both `enableBiometrics` and `disableBiometrics` need a `.settings`
  session verified with the code, so the toggle opens a "current
  passcode" page (`PasscodeMode.touchId(enable:)`). If enabling throws
  (cancelled prompt, `biometricsUnavailable`) the passcode stays as it
  was, a short text says so, and the toggle stays off.
- Carry-over: after a successful code at the launch lock or the runtime
  lock, users with `useTouchId = true` get `verify(.settings)` +
  `enableBiometrics` (one Touch ID prompt). The old setting is cleared
  after one attempt whatever the result, and also when Touch ID is
  already on or there is no passcode; it is kept when the sensor is
  missing or the store cannot be read. Any explicit toggle clears it too.
- Runtime lock: `authenticateBiometrics` with `.resource("telex.db")`
  (PasscodeCore issues Touch ID sessions for resource scopes only), the
  session is invalidated at once; the old `LAContext` policy check and its
  device-password fallback are gone.
- Launch lock: `.needsPasscode(offersTouchId:)`; Touch ID is tried when
  the lock appears (or the window becomes key) and from its button. A
  launch-once guard covers Touch ID and a typed code both succeeding;
  closing the lock invalidates the `LAContext`, which cancels a pending
  prompt. Prompts run on their own queue so a typed code is still checked.
- New English-only texts: the enable prompt reason and "Touch ID was not
  turned on".
- Tests: MacPasscode 74 (new: policy table, carry-over success / failure /
  skip / clear cases, Touch ID offered only for protected `v2`, same key
  as the code, cancel leaves the code working); ApiCredentials 25;
  PasscodeAccessChallenge 6. Debug build check passes. The new build was
  not launched (the user's Telex owns the data folder).

### Task 8: Share extension unlock
**Files:**
- Modify: `TelegramShare/ShareViewController.swift`
- Modify: `TelegramShare/SEPasslockController.swift`

- [x] configure `PasscodeEnvironment` with `.appExtension` and the same
      scope; account manager with its own read-only
      `AccountManagerAccessChallenge` (`isReadOnly: true`), not
      `setupAccountManager` (see results)
- [x] unlock with `verify` and unseal `db-key.v2`; never migrate, write
      key material or reset from the extension; no Touch ID (refused for
      extensions by design)
- [x] only the legacy file present → "Open Telex once to finish the
      update"
- [x] tests for the extension's decision helper (wrong code, legacy-only,
      credential lost); run all unit tests and the build check

**Results** (2026-10-17).
- MacPasscode `ReadOnlyUnlock` (new): states `ready(needsPasscode:)`,
  `needsAppLaunch` (live legacy file, also next to `db-key.v2` after an
  interrupted migration, or no key file at all), `credentialLost`
  (`db-key.v2` without credential, or a retired legacy file without
  `db-key.v2`). It only sees `CredentialReader` (`hasStoredCredential`,
  `isProtectionEnabled`, `databaseSealingKey`), now the base protocol of
  `LaunchCredentialStore`, and wraps the file storage so writes and
  removes throw `.readOnly`: it cannot migrate, retire, reset or create.
- `MacPasscodeEnvironment.configure(.appExtension)` also calls
  `requireExistingCredential()`, so PasscodeCore throws `.unavailable`
  instead of creating a credential (`unprotectedSession` would otherwise
  create one if the item vanished after the state check).
- Account manager: `prepare` checks the shared group and sets the
  cross-process lock (`accounts-metadata/passcode-v1.lock`), no reset;
  `resolve` returns the stored value unchanged. The core's resolver is not
  used even without migration: `getAccessChallengeData` calls it with
  `allowMigration: true` and writes back any differing answer, which a
  read-only account manager must not do.
- `ShareViewController`: no passcode → unseal silently; passcode →
  `SEPasslockController`, checked on a background queue (wrong code
  shakes, cooldown shakes and shows the seconds under the field, further
  submissions ignored while a check runs); `needsAppLaunch` → "Open Telex
  once to finish the update, then share again."; credential lost, keychain
  or unseal errors, missing keychain prefix → "…keychain item is missing or
  unreadable. Open Telex to fix this." English only. No reset anywhere.
- TelegramShare no longer uses `AppEncryptionParameters`, `.passthrough`,
  `BuildConfig` or `PasscodeAccessChallenge` (unlinked; MacPasscode linked
  instead), and its Info.plist has `TGKeychainGroupPrefix`; the built
  appex shows `2FKX9S8MFA.`.
- Tests: MacPasscode 88 (new 14: unlock with / without passcode and after
  a fresh install, wrong code, cooldown, legacy-only with and without
  passcode, `.tempkey`, interrupted migration, no key, credential lost,
  retired file without `db-key.v2`, keychain error, unreadable file,
  storage refusing writes; every case asserts no file write, no credential
  change and no store call besides `databaseSealingKey`); ApiCredentials
  25; PasscodeAccessChallenge 6. Debug build check passes; the appex is
  signed with only `…telex.shared`, `codesign --verify --deep --strict`
  passes. Not launched (the user's Telex owns the data folder; a real share
  is in Post-Completion).

### Task 9: Remove the old storage and the adapter
**Files:**
- Delete: `packages/PasscodeAccessChallenge`
- Modify: `submodules/BuildConfig/Sources/BuildConfig.m`, `BuildConfig.h`
- Modify: `Telegram.xcodeproj/project.pbxproj`

- [x] delete the adapter package and its tests
- [x] remove `AppEncryptionParameters` (or keep only what
      `LegacyKeyReader` needs), plus the unused `encryptData` /
      `decryptData` and the old `.tempkey` upgrade; record whether
      `.tempkey`-only installs are still supported
- [x] `git grep` finds no remaining users
- [x] run all unit tests and the build check

**Results** (2026-10-17).
- `packages/PasscodeAccessChallenge` deleted and unlinked from
  `project.pbxproj` (file reference, group entry, the app's framework
  build file and product dependency; TelegramShare was unlinked in
  Task 8).
- `submodules/BuildConfig` is a plain directory in this repo, edited
  directly. `AppEncryptionParameters` is gone with `encryptData` /
  `decryptData` and the `.tempkey` upgrade, plus the `MurMurHash32` and
  `CryptoUtils` dependencies only it used. Kept, as still declared in
  the header: `DeviceSpecificEncryptionParameters` (returned by
  `BuildConfig.deviceSpecificEncryptionParameters`), `LocalPrivateKey`
  and `BuildConfig`. No Swift code uses any of them today (the four
  `import BuildConfig` lines are leftovers); removing the module is out
  of scope.
- `.tempkey`-only installs remain supported: `LegacyKeyReader` (Task 5)
  reads a 48-byte `.tempkey` as an unprotected key and the launch
  migration moves it to `db-key.v2`.
- `git grep` (excluding `submodules/telegram-ios` and `docs/plans`) finds
  no users of `AppEncryptionParameters`, `PasscodeAccessChallenge`,
  `storeAccessChallengeData` or the passcode `.passthrough`; two
  MacPasscode doc comments still name the old class as history.
- INSTALL.md: the PasscodeAccessChallenge test command is replaced by
  the MacPasscode one.
- Tests: MacPasscode 88, ApiCredentials 25. Debug build check passes.

### Task 10: Verify acceptance criteria
- [x] fresh install: launch works, `db-key.v2` exists, the legacy file is
      a retired marker (Task 6) (unit test and real-keychain harness, not
      the app; see results)
- [x] legacy install with and without a passcode (fixture built by the
      old code path in a test): first unlock migrates, protection is on
      when a code was set, the legacy file is poisoned
- [x] all unit tests and the build check pass
- [x] launch the Debug build once from the terminal and quit it (do not
      kill processes you did not start) (skipped - launching would
      migrate the user's real data; left for the user after backup)

**Results** (2026-10-17).
- Unit tests: MacPasscode 89 (new
  `testMigratesFilesWrittenByOldCode`: all five old-code fixtures, with
  and without a passcode, go through `LaunchUnlock`: a wrong code changes
  nothing, the first unlock returns the old key, protection matches the
  passcode, the legacy file is retired, `db-key.v2` opens with the same
  key; the fixture type is now shared as `LegacyFixture`); ApiCredentials
  25; FoundationUtils 30. `testFreshInstall` covers the fresh case.
- Real keychain: a scratchpad harness (`MacPasscodeEnvironment`,
  `CoreLaunchCredentialStore`, `LaunchUnlock` on disk), signed like the
  Debug app (bundle ID `com.korthane.telex`, the built Telex.app's
  entitlements incl. `…telex.private`, development profile), in a
  temporary folder, one process per scope `com.korthane.telex.spike.accept-*`.
  All 23 checks pass: fresh → `createFresh`, `db-key.v2` exists, legacy
  file retired, relaunch is `v2(needsPasscode: false)` with the same key;
  old-code file without passcode → migrates, protection off; old-code file
  with `1234` → `0000` refused and nothing written, then migrates,
  protection on, `.secured` stored, relaunch needs the code and opens the
  same key. Cleanup: `resetCredential` per scope, all `.spike.accept-`
  items deleted, none left in the data protection or login keychain;
  temporary folder removed.
- Debug build check passes. Release build (`-configuration Release`, no
  provisioning flags needed) passes: Telex.app and TelegramShare.appex are
  signed `Developer ID Application: Korthane LLC (2FKX9S8MFA)`, hardened
  runtime, sandboxed, profiles `Telex Developer ID`
  (`be513007-…`) and `Telex Share Developer ID` (`df46f97f-…`), both
  `ProvisionsAllDevices`; `keychain-access-groups` = `…telex.shared` +
  `…telex.private` (app), `…telex.shared` (appex); `codesign --verify
  --deep --strict` passes; `spctl` rejects it as unnotarized, as expected.
- ⚠️ Both Release bundles carry `com.apple.security.get-task-allow` =
  true: `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` resolves to YES for Release
  (Xcode default; only an archive export strips it). Notarization rejects
  that entitlement, so a notarized release needs
  `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` for Release or an
  archive/export. Not changed here (signing settings are out of scope).
  Fixed in the review: Release now sets it to NO; a rebuilt Release
  bundle and appex show no `get-task-allow`.
- Not launched: no switch moves the data root (`ApiEnvironment.dataRootURL`
  is always the app group container), so any launch would migrate the
  user's real `debug/` data. Left for Post-Completion after a backup.

### Task 11: [Final] Update documentation
- [x] INSTALL.md: passcode in PasscodeCore / data protection Keychain; data depends
      on that keychain item ("Log out and reset" if lost); Touch ID; Share
      extension needs Telex opened once after the update; downgrading
      after the update cannot open local data; update the test-command
      lines that mention PasscodeAccessChallenge
- [x] remove the passcode item from `nogit_todo.md`
- [x] update CLAUDE.md if a non-obvious rule came up
- [x] move this plan to `docs/plans/completed/` (done by the exec
      completion step)

**Results** (2026-10-17).
- INSTALL.md (Notes): the data protection Keychain (not the login
  keychain, after Task 2/3), per build type; local data depends on the
  item, "Quit" / "Log Out and Reset" if lost; the first start migrates
  the old key file irreversibly (back up first, no downgrade); Touch ID
  asks for the passcode, one prompt for the carry-over; the Share
  extension needs Telex opened once and has no Touch ID; Release still
  carries `get-task-allow` (Task 10 ⚠️, unchanged), so not notarizable
  (fixed in the review, see below).
  The signing steps (Task 2) and the MacPasscode test line (Task 9) were
  already there.
- `nogit_todo.md` (untracked): passcode item removed from "Finish the
  move"; the manual checks point to Post-Completion.
- CLAUDE.md: one rule on the patch, profiles, `migrateLegacyItems`,
  `setupAccountManager` and `ReadOnlyUnlock`.

### Review fixes (2026-10-17)
- A marker migration interrupted after the credential took the code no
  longer drops the passcode: while the old key file is live, a credential
  that holds a passcode makes `state()` ask for it, and only the
  credential checks it (no reset on a wrong code). The no-code migration
  never resets a credential with a passcode; it resets an unmanaged one so
  the account manager accepts `.none`.
- A crash after `db-key.v2` was written but before the old file was
  retired is finished by the next `.v2` unlock (retired marker, `.none`).
- The runtime logout reset no longer deletes key files:
  `LaunchUnlock.resetCredential(keeping:)` resets the credential, then
  overwrites `db-key.v2`; a failure shows Try Again / Quit instead of a
  log line. `sealAfterReset` and `offersBiometrics` are gone.
- Cold start: one main-queue launch claim covers Touch ID, the typed
  code, Log Out and the error alert; claiming cancels a pending Touch ID
  prompt. Cold-start Log Out clears account records only after the reset
  worked. The settings Touch ID prompt runs on the biometric queue.
- Key files are written with `F_FULLFSYNC` on the file and directory.
- Tests: crash loops for the marker path, a stale credential and the
  runtime reset; a contract suite and two crash loops run against the
  real `PasscodeCredentialStore` over in-memory items (`@testable`);
  `MacPasscodeEnvironment.configure` per role.
- Release configs set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` for Telex
  and TelegramShare, so Release bundles no longer carry `get-task-allow`.

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
- Delete the scoped Keychain items by hand → "Log Out and Reset" appears
  and works.
- Log out from the lock screen; next launch starts clean.
- Debug and Release: a passcode in one does not lock the other.
- Sandboxed Release build: all of the above.
