# Update telegram-ios core and enable the Rust MTProto engine

## Overview
- Fast-forward `submodules/telegram-ios` from `6ad963e5` (2026-07-18) to
  upstream `TelegramMessenger/Telegram-iOS` master (`f1dd7a2d`, 2026-10-07,
  829 commits).
- Gains: about 20 Postbox fixes (crashes, leaks, read counters, media cache,
  SQLCipher 4.19.0), MtProtoKit security hardening, leak and proxy-storm
  fixes, API layer 215, and ffmpeg 8.1.2.
- Turn on the Rust MTProto engine as upstream does on macOS, in the main app
  **and** the Share extension.
- No new Mac UI for upstream features (rich text, ephemeral messages, welcome
  messages and so on). Those get their own plans. Only fix call sites that
  break after the bump.

## Context (from discovery)
- The Mac app uses these telegram-ios modules: TelegramCore, Postbox,
  TelegramApi, MtProtoKit, SSignalKit, ffmpeg, MetalEngine, MediaPlayer,
  TelegramVoip, EncryptionProvider/OpenSSLEncryptionProvider, Utils and a
  few small ones.
- `scripts/configure_frameworks.sh` builds the native libraries, ffmpeg
  among them, into `core-xprojects/*/build` and applies
  `patches/<submodule>/*.patch`. The patches for telegram-ios are
  `getconfig-with-layer`, `metalengine-compile-shaders`, `story-sync-pacing`
  and `telegramcore-no-warnings-as-errors`.
- Upstream removed `ffmpeg-7.1.1`, so only `ffmpeg-8.1.2` remains.
  `core-xprojects/ffmpeg/ffmpeg/build.sh:32` hardcodes `FF_VERSION="7.1.1"`.
  The ffmpeg project runs `build.sh` only when `core-xprojects/ffmpeg/build`
  is missing.
- The telegram-ios working tree is dirty: `configure_frameworks.sh` applied
  the patches in place. Also, `TgVoipWebrtc/tgcalls` and
  `third-party/webrtc/webrtc` are checked out at commits other than the
  recorded ones.
- Patch dry run against upstream: `getconfig-with-layer`,
  `metalengine-compile-shaders` and `story-sync-pacing` apply cleanly.
  `telegramcore-no-warnings-as-errors` fails on context, because upstream
  added a `MediaPreuploadRegistry` dependency. It is still needed.
- Rust engine wiring upstream:
  - `submodules/MTProtoRustEngine` is a SwiftPM package. It depends on
    TelegramCore, MtProtoKit, SSignalKit, EncryptionProvider and the new
    `submodules/WebProxyTransport`, plus a binary target
    `MTProtoEngineFFI.xcframework`. That xcframework is git-ignored and built
    from `third-party/mtproto-engine` (a new submodule,
    `github.com/macosswift/mtproto-engine`).
  - The app passes `networkEngineFactory:` to `NetworkInitializationArguments`.
    `NetworkEngineSettings.defaultSettings` is `.rust` on macOS, and the
    `mtproto_engine_rust_disabled` server app config forces MtProtoKit.
  - `RustNetworkEngineFactory` (public struct with `init()`) has
    `supportsWebProxy == true`.
  - The crate gets hardware AES from `.cargo/config.toml`
    (`--cfg aes_armv8`). Cargo reads that file based on the working
    directory, so the build must run from the crate directory.
  - In an `.appex`, TelegramCore never turns on the WEB proxy carrier, so a
    WEB proxy does not work in Share whichever engine runs. The Mac app
    can't use one either: nothing on the Mac creates a `.web` proxy (no
    `webproxy` link parsing, no editor type) and the Mac never installs a
    carrier view host (`WebProxyTransport.shared.setViewHost`), so WEB
    proxies are out of scope here and need their own plan.
  - `RustNetworkEngineFactory.makeEngine(context:isAppExtension:)` returns
    nil when `isAppExtension` is true. That is why upstream extensions stay
    on MtProtoKit.
- Mac call sites:
  - `Telegram-Mac/NetworkInitializationArguments.swift`
    (`makeNetworkInitializationArguments`), used by `AppDelegate.swift:898`
    and `ApiCredentialsChecker.swift:24`.
  - `TelegramShare/ShareViewController.swift:146`, which builds the
    arguments inline.
- Toolchain: rustup; the crate pins Rust 1.96.1 (`rust-toolchain.toml`),
  installed alongside the stable default. The `aarch64-apple-darwin`
  target is installed.

## Development Approach
- **testing approach**: Regular (code first, then tests). Most of the work
  is build fixes with no new testable logic. Verify by building, the
  existing package tests, upstream's `MTProtoRustEngine` tests, and the
  runtime log checks listed in each task.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in
  that task, or the build or runtime check that stands in for them when the
  change is build wiring
- **CRITICAL: all tests must pass before starting next task** - no exceptions
- **CRITICAL: update this plan file when scope changes during implementation**
- maintain backward compatibility. Existing account data must open after
  the upgrade, and Postbox migrations run on first start.

## Testing Strategy
- **unit tests**: `cd packages/FoundationUtils && swift test`,
  `cd packages/ApiCredentials && swift test`,
  `cd packages/PasscodeAccessChallenge && swift test` (passcode marker
  round trip against a real `AccountManager`), and
  `cd submodules/telegram-ios/submodules/MTProtoRustEngine && swift test`
  (mapping and bridge tests; the end-to-end tests may need network access).
- **upstream tests** (patches applied; failures are upstream's, record them,
  don't fix): `cd submodules/telegram-ios/submodules/TelegramCore && swift test`.
  Postbox has no SwiftPM test target (its `Tests/` run under Bazel only),
  so there is no `swift test` for it.
- **build check** (after every task):
  ```
  xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath ~/build/TelegramSwift -allowProvisioningUpdates build
  ```
- **e2e tests**: none. Manual checks are listed in Post-Completion.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update plan if implementation deviates from original scope
- keep plan in sync with actual work done

## Solution Overview
- Step 1: move the submodule and get the existing app building again on
  MtProtoKit, with no factory passed. That isolates bump breakage from Rust
  engine breakage.
- Step 2: build `MTProtoEngineFFI.xcframework` from
  `third-party/mtproto-engine` inside `configure_frameworks.sh`. Add the
  `MTProtoRustEngine` package to the workspace (`WebProxyTransport` comes in
  through TelegramCore) and pass the factory.
- Share extension: add a small Mac-side factory wrapper that forwards
  `makeEngine` with `isAppExtension: false`. This avoids patching
  telegram-ios. The wrapper still honours the factory's other refusals, such
  as datacenter overrides or a missing engine runtime, so MtProtoKit
  remains the fallback.

## Technical Details
- Wrapper (shared by the app and Share; it lives where both targets compile it):
  ```swift
  struct ExtensionAllowingRustEngineFactory: NetworkEngineFactory {
      let base = RustNetworkEngineFactory()
      func makeEngine(context: MTContext, isAppExtension: Bool) -> NetworkEngine? {
          // <reason taken from mtproto-engine docs, see Task 5>
          base.makeEngine(context: context, isAppExtension: false)
      }
      var supportsWebProxy: Bool { base.supportsWebProxy }
  }
  ```
  The factory still declines datacenter overrides and a missing runtime.
- Engine choice is stored under the `engine_v2` key in
  `NetworkEngineSettings`, with `.rust` as the macOS default. No Mac
  setting UI is added.
- To check which engine runs, look for the Logger lines
  `Network: Account N: engine rust` and `[MTProtoRust] declined: ...`.

## What Goes Where
- **Implementation Steps**: the submodule bump, patch rebases, build
  script, workspace and package wiring, Swift call-site fixes, the factory
  wrapper, and docs.
- **Post-Completion**: manual login, sync, media, proxy and Share checks on
  a real account, plus a Release build.

## Implementation Steps

### Task 1: Fast-forward the submodule and rebase local patches

**Files:**
- Modify: `submodules/telegram-ios` (gitlink)
- Modify: `patches/telegram-ios/*.patch`

- [x] record the current gitlink `6ad963e5` in this plan for rollback
      (rollback: `6ad963e5b62d354da79040f388ae2b9132fb17b8`)
- [x] reverse the applied patches (`git -C submodules/telegram-ios apply -R
      ../../patches/telegram-ios/*.patch`) so the four modified files are
      clean. Leave the `tgcalls` and `webrtc` nested checkouts alone
- [x] `git -C submodules/telegram-ios checkout f1dd7a2d` (or the newest
      upstream master at execution time, recorded here). Upstream master
      was still `f1dd7a2dbd` on 2026-10-11; checked out that commit
- [x] init only the new nested submodule:
      `git -C submodules/telegram-ios submodule update --init
      third-party/mtproto-engine`. Do not use `--recursive` on the whole
      repo, because it would move `tgcalls` and `webrtc`. Update other
      nested submodules only where the Mac build uses them and upstream
      moved them. `mtproto-engine` is at `0de759a3`. No Mac build file
      uses the other moved or new nested submodules (`rlottie`, `tlottie`,
      `wallet-engine`, bazel rules), so they stay as they are
- [x] regenerate `telegramcore-no-warnings-as-errors.patch` against the new
      `TelegramCore/Package.swift`. Confirm that the other three still
      apply with `git apply --check`
- [x] gate: `git apply --check` passes for all four patches

### Task 2: Rebuild native libraries with ffmpeg 8.1.2

**Files:**
- Modify: `core-xprojects/ffmpeg/ffmpeg/build.sh`
- Modify: `scripts/configure_frameworks.sh` (only if needed)
- Modify: `core-xprojects/ffmpeg/ffmpeg.xcodeproj/project.pbxproj` (only if needed)

- [x] set `FF_VERSION="8.1.2"` in `core-xprojects/ffmpeg/ffmpeg/build.sh`.
      Diff its `CONFIGURE_FLAGS` against upstream
      `submodules/ffmpeg/Sources/FFMpeg/build-ffmpeg-bazel.sh`. Kept the Mac
      flags: upstream only adds the `av1` decoder and `ogg` muxer, which the
      Mac never had, and every Mac component exists in ffmpeg 8.1.2
- [x] delete `core-xprojects/ffmpeg/build` and rerun
      `CMAKE_POLICY_VERSION_MINIMUM=3.5 sh scripts/configure_frameworks.sh`
- [x] fix any configure options that ffmpeg 8 removed or renamed (none:
      configure ran with no warnings, built FFMPEG_VERSION 8.1.2,
      libavcodec 62)
- [x] fix `FFMpegBinding` and `MediaPlayer` header-path breakage
      (`SharedHeaders/ffmpeg/include`) (none: headers copied by the script,
      FFMpegBinding compiles)
- [x] check that the script's patch loop applies cleanly on a fresh
      checkout. Running it a second time must be a no-op (reversed all four
      patches, ran the loop twice, identical diffs)
- [x] the build check compiles past the native-library stage (Swift errors
      are allowed until Task 3). First Swift error:
      `ManageSharedAccountInfo.swift:60` switch must be exhaustive
      (TelegramShare)

### Task 3: Fix Mac call sites for the new TelegramCore and Postbox APIs

**Files:**
- Modify: Swift files under `Telegram-Mac/`, `TelegramShare/` and
  `packages/*` that fail to compile
- Modify: `packages/*/Package.swift` if upstream package names or
  dependencies changed (for example, the new `WebProxyTransport` dependency
  of TelegramCore)

- [x] **before any run**: back up the app-group data folder. The
      Postbox/SQLCipher 4.19 migration on first start can't be undone.
      Backup: `~/Backups/3PB2Z94Q5T.dev.alek.telegram.backup-20261011`
      (macOS refuses new folders inside `~/Library/Group Containers/`)
- [x] run the build check and collect the errors. Group them by module
      and add a sub-item per group here with ➕
  - ➕ proxy: new `ProxyServerConnection.web(secret:path:)`. Only made
    exhaustive, since the Mac can't add a WEB proxy: labelled like MTProto
    (no calls), link via `webProxySettingsLink` (no link, copy or QR when
    that returns nil), the editor ignores edits to one, shared account
    info skips it (deliberate; nothing reads those infos back)
  - ➕ account manager: `AccountManager.init` needs `accessChallenge:`.
    Mac passes `.passthrough`, and passcode writes go through
    `storeAccessChallengeData`, since the core now commits only what the
    resolver returns. `.secured` passcode shows as enabled. ➕ Both live in
    `packages/PasscodeAccessChallenge` with tests against a real
    `AccountManager` (store, reopen read-write and read-only, clear, plain
    set dropped, `.numericalPassword`/`.secured` open unchanged)
  - ➕ instant view: `RichText.textButton`/`textTonAddress` render as
    plain text; `.table` gained `compact` (ignored)
  - ➕ text entities: `MessageTextEntityType.TonAddress` (weight 24,
    no link UI)
  - ➕ gifts: `starGiftUnique` action gained `text`, `entities`,
    `nameHidden`; with `nameHidden` the sender is left out of the
    message's peers, so the Mac shows "Unknown user" instead of falling
    back to the message author; `.starGiftResale` source needs
    `hideName`/`text`/`entities` (false/nil);
    `UpgradeStarGiftError.alreadyUpgraded` shows the generic error
  - ➕ bots: `UpdateCustomVerificationValue.enabled` needs
    `descriptionEntities` (nil)
- [x] fix renamed or changed APIs with the smallest change that keeps
      current behaviour. Where an enum gained new cases (new message media,
      actions, button kinds), add a neutral fallback, not new UI
- [x] fix the Share extension target the same way (WEB proxy in
      shared account info, `accessChallenge:` in ShareViewController)
- [x] build the Release configuration once to catch `#if DEBUG`-only paths
- [x] run the package tests (`FoundationUtils`, `ApiCredentials`). They
      must pass
- [x] ⚠️ run the Debug app and confirm that the existing account opens (the
      Postbox migration runs), the chat list loads and a message sends.
      The engine is still MtProtoKit at this point, with no factory passed
      (not run — needs manual run; only the Debug and Release builds were
      checked)

### Task 4: Build MTProtoEngineFFI.xcframework

**Files:**
- Modify: `scripts/configure_frameworks.sh`

- [x] find the xcframework build script or instructions in
      `third-party/mtproto-engine` (README, `scripts/`, `Makefile`). Check
      for a pinned `rust-toolchain.toml`. The crate has no xcframework
      script; `docs/swift-integration.md` §2 describes upstream's Mac
      `build.sh`, which this repo lacks. The toolchain is pinned to 1.96.1
      (installed with rustup)
- [x] add a step to `configure_frameworks.sh` that runs from the crate
      directory, so `.cargo/config.toml` (hardware AES) applies. It builds
      `--release` for `aarch64-apple-darwin` only and places the result at
      `submodules/telegram-ios/submodules/MTProtoRustEngine/MTProtoEngineFFI.xcframework`.
      Run the crate's link-verify script if it has one.
      `scripts/verify-ios-link.sh` needs a linked binary, so it is not in
      the script; run by hand on the `MTProtoRustEngineTests` binary: one
      std, 72 AES instructions in mtproto_core. Its SHA-256 check reports
      FAIL only because it expects v0 mangling; `otool` shows 32
      `sha256h` in `sha2::sha256::compress256`
- [x] fail early with a clear message when `rustup` is missing (checked
      at the top of the script, `~/.cargo/bin` put first on `PATH`). The
      script reads the channel from `rust-toolchain.toml` (fails clearly
      if it can't), runs `rustup toolchain install <channel> --profile
      minimal --target aarch64-apple-darwin` (a no-op once installed) and
      builds with `rustup run <channel> cargo`, so a Homebrew cargo
      earlier on `PATH` can't replace the pinned toolchain
- [x] run `shellcheck scripts/configure_frameworks.sh` and fix what it
      reports (no new findings; the 20 older ones are untouched)
- [x] run `cd submodules/telegram-ios/submodules/MTProtoRustEngine && swift test`.
      The mapping and bridge tests must pass. Record any network-dependent
      end-to-end failures here with ⚠️ (all 65 pass, end-to-end included,
      after `cargo build --release -p mtproto-testserver`)

### Task 5: Wire the Rust engine into the app and the Share extension

**Files:**
- Modify: `Telegram-Mac.xcworkspace` / `Telegram.xcodeproj/project.pbxproj`
  (add the `MTProtoRustEngine` local package and link it to the Telegram
  and TelegramShare targets)
- Create: `Telegram-Mac/ExtensionAllowingRustEngineFactory.swift` (member
  of both targets)
- Modify: `Telegram-Mac/NetworkInitializationArguments.swift`
- Modify: `TelegramShare/ShareViewController.swift`

- [x] read `third-party/mtproto-engine/docs/swift-integration.md` for why
      extensions are declined. If the reason applies on macOS (for example,
      shared state with the main app), stop and ask before overriding it.
      Write the wrapper comment from what the docs say. The only reason
      given (`docs/research/integration.md` §5) is "until the engine passes
      the NSE memory budget", an iOS notification-service limit, so the
      wrapper is used
- [x] add `MTProtoRustEngine` the same way TelegramCore is added, and check that the xcframework embeds and
      signs in both the app and the appex (a static library needs no embed;
      check what the FFI produces). The FFI is a static `.a`; `nm` shows the
      `mt_engine_*` symbols in both Release binaries, nothing to embed, and
      `codesign --verify --deep --strict` passes
- [x] create `ExtensionAllowingRustEngineFactory` as in Technical Details
- [x] pass `networkEngineFactory: ExtensionAllowingRustEngineFactory()` in
      `makeNetworkInitializationArguments` and in
      `ShareViewController`. Also pass it in `ApiCredentialsChecker`
      through the shared function
- [x] build the Debug and Release configurations
- [x] ⚠️ runtime check for the app: the log shows `engine rust` for the
      account, and login, chat-list sync and a media download work
      (not run — needs manual run)
- [x] ⚠️ runtime check for Share: share a file into a chat, and the Share log
      shows `engine rust` with no `[MTProtoRust] declined: app extension`
      (not run — needs manual run)
- [x] ⚠️ runtime check for the credentials check: Settings → API credentials
      accepts valid values and reports an API_ID error for an invalid id,
      under Rust (not run — needs manual run)
- [x] ⚠️ runtime check for a proxy: set a SOCKS5 proxy in Settings, and the
      network keeps working (not run — needs manual run)
- [x] run the package tests and the `MTProtoRustEngine` tests. They must
      pass (FoundationUtils, ApiCredentials, MTProtoRustEngine 65/65)

### Task 6: Verify acceptance criteria
- [x] `git -C submodules/telegram-ios rev-parse HEAD` equals the target
      commit and every local patch applies (`f1dd7a2dbd`; all four
      patches pass `git apply --check -R`, i.e. are applied)
- [x] a fresh `git clone --recurse-submodules` from the local path into
      the scratch directory, plus `configure_frameworks.sh` plus the build
      check, succeeds (all nested submodules fetched, 10 native projects
      and the xcframework built, Debug BUILD SUCCEEDED; clone deleted)
- [x] ⚠️ the app and Share both log `engine rust` (not run — needs manual
      run)
- [x] ⚠️ fallback: temporarily set `updateNetworkEngineSettings(accountManager:)
      { _ in .init(engine: .mtProtoKit) }`. The log shows
      `engine mtProtoKit` and the app works. Then revert
      (not run — needs manual run)
- [x] run the full test suite: FoundationUtils, ApiCredentials and
      MTProtoRustEngine `swift test` (19, 40 and 65 tests, 0 failures)
- [x] ➕ PasscodeAccessChallenge `swift test` (5 tests, 0 failures)
- [x] ➕ ⚠️ upstream TelegramCore `swift test` (patches applied): 166 tests,
      164 pass, `ProxySettingsTests` included. Two upstream failures in
      `ApiConstructorCompatibilityTests`
      (`testUserFullParsesWithAndWithoutTheGramAddressLayout`,
      `testWalletUserAddressParsesBothLayouts`: the older TL layouts no
      longer parse). Not ours; left as is. Postbox has no SwiftPM test
      target to run
- [x] the Release build succeeds and is signed (`codesign --verify --deep`)
      (`--deep --strict` passes, team 3PB2Z94Q5T, appex validated)

### Task 7: [Final] Update documentation
- [x] in `INSTALL.md`, add rustup/cargo to the tools, say that the Rust
      engine is built by `configure_frameworks.sh`, and how to tell which
      engine runs (log lines)
- [x] update README.md if needed (not needed: it states nothing the update made wrong)
- [x] move plan (done by orchestrator at completion)

## Post-Completion
*Items requiring manual intervention or external systems - no checkboxes, informational only*

**Manual verification**:
- Runtime checks ticked with ⚠️ above, none of them run yet:
  - first start of the Debug app on existing data (Postbox/SQLCipher 4.19
    migration; back up the app group folder first), chat list loads, a
    message sends;
  - the app log shows `Network: Account N: engine rust`, and login,
    chat-list sync and a media download work;
  - sharing a file through the Share extension works and its log shows
    `engine rust` with no `[MTProtoRust] declined: app extension`;
  - Settings → API credentials under Rust accepts valid values and reports
    an API_ID error for an invalid id;
  - a SOCKS5 proxy keeps the network working under Rust;
  - forced MtProtoKit (`updateNetworkEngineSettings` set to
    `.mtProtoKit`, then reverted) logs `engine mtProtoKit` and works.
- Passcode: turn the passcode on and off, restart in between, and check
  that the Share extension asks for it while it is on.
- On a real account over a day of normal use: calls, voice and video
  messages (ffmpeg 8), stickers and animated emoji, large file
  upload/download (the CDN path in the Rust engine), and wake from sleep
  with a network change.
- Share extension on a large file and on several items.
- MTProxy and SOCKS5 proxies in the main app.
- Known limitation: WEB proxies are not supported on the Mac yet. The app
  can't add one, and it never installs the carrier's view host; the Share
  extension never turns on the carrier at all.

**Follow-ups (separate plans)**:
- Mac UI for new upstream features: rich-text messages and editor,
  ephemeral messages, welcome messages, anchored reporting, gift resale,
  InstantPage buttons and tables.
- Consider SwiftSignalKit2 and GraphCore2 (upstream's macOS-specific
  rewrites).
- WEB proxy support on the Mac: `tg://webproxy`/`t.me` link parsing, a WEB
  type in the proxy editor, and a carrier view host
  (`WebProxyTransport.shared.setViewHost`).
