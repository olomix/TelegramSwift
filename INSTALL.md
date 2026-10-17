# How to Build Telegram for macOS

This fork builds for Apple Silicon only, requires macOS 27 and Xcode 27,
and builds `Telex.app`, which runs as `com.korthane.telex`, separate from
the official Telegram app.

## One-time setup

1. Clone with submodules:
	```
	git clone https://github.com/olomix/TelegramSwift.git --recurse-submodules
	```
2. Install build tools:
	```
	brew install cmake ninja meson yasm nasm pkg-config
	xcodebuild -downloadComponent MetalToolchain
	```
   Install Rust with [rustup](https://rustup.rs), which also gives you
   `cargo`. The Rust MTProto engine pins its Rust version in
   `rust-toolchain.toml`; `configure_frameworks.sh` installs that version
   with rustup. The first run downloads the pinned Rust toolchain and the
   crate dependencies, so it needs network access.
3. Set your Apple team for code signing:
	```
	cp Telegram-Mac/Secrets.example.xcconfig Telegram-Mac/Secrets.xcconfig
	```
   and fill in `DEVELOPMENT_TEAM` (your Apple team ID, shown in Xcode →
   Settings → Accounts). It is required: the app and the Share extension
   share data through an app group, and the group name starts with the team
   ID. Debug and Release builds are both signed with this team as
   "Apple Development" by default. The file is git-ignored; never commit it.
4. Register the App IDs and get provisioning profiles. The app and the
   Share extension share Keychain items through the access group
   `<TeamID>.com.korthane.telex.shared` (`keychain-access-groups`); the
   app also uses the app-only group `<TeamID>.com.korthane.telex.private`.
   macOS allows these only with a provisioning profile, so a paid
   developer team is required.
   - In the [developer portal](https://developer.apple.com/account/resources/identifiers/list)
     register the App IDs `com.korthane.telex` and
     `com.korthane.telex.TelegramShare`, both with the App Groups
     capability. Keychain Sharing is not needed: every macOS profile
     allows the team's own access groups.
   - Debug: signing is automatic. Build once in Xcode, or pass
     `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` to
     `xcodebuild` (as below). Xcode registers this Mac and creates the
     "Mac Team Provisioning Profile" for each App ID.
   - Release (optional, for builds you give to others): create Developer
     ID provisioning profiles for both App IDs, install them, and set
     `TELEX_RELEASE_SIGN_STYLE`, `TELEX_RELEASE_SIGN_IDENTITY`,
     `TELEX_APP_PROFILE` and `TELEX_SHARE_PROFILE` in `Secrets.xcconfig`
     (see `Secrets.example.xcconfig`). Without them Release is signed like
     Debug.
5. Build the native libraries (takes 20+ minutes). Repeat after updating
   submodules:
	```
	CMAKE_POLICY_VERSION_MINIMUM=3.5 bash scripts/configure_frameworks.sh
	```
   This also applies the local fixes in `patches/<submodule>/` to the
   submodules and builds the Rust MTProto engine
   (`MTProtoEngineFFI.xcframework`). If a pull only changes
   `patches/<submodule>/`, the script resets that submodule and re-applies
   its patches itself.

   In an existing clone, after pulling a submodule update, discard the
   previously applied patches (the script re-applies the current ones),
   pick up changed submodule URLs and fetch the engine's nested submodule
   before running the script:
	```
	git -C submodules/tgcalls checkout -- .
	git -C submodules/tg_owt checkout -- .
	git -C submodules/telegram-ios checkout -- .
	git -C submodules/libprisma checkout -- .
	git submodule sync submodules/tgcalls submodules/tg_owt
	git submodule update --init
	git -C submodules/telegram-ios submodule update --init third-party/mtproto-engine
	```
   Don't use `--recursive` on the whole repo: it moves telegram-ios's own
   nested `tgcalls` and `webrtc` checkouts.
   If you built before the ffmpeg 8.1.2 update, run
   `rm -rf core-xprojects/ffmpeg/build` first; ffmpeg is rebuilt only when
   that folder is missing. WebRTC is rebuilt automatically when the
   `tg_owt` commit, `patches/tg_owt/` or
   `core-xprojects/webrtc/webrtc/build.sh` change.

   `patches/tg_owt/tgcalls-seams.patch` ports the WebRTC hooks tgcalls
   uses for MTProto-in-DTLS and `GroupInstanceReferenceImpl`, which only
   iOS's WebRTC fork has. Its header lists the source commits and rebase
   notes; a `tg_owt` update must keep it applying.

## Build and run from the console

```
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ~/build/TelegramSwift \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

open ~/build/TelegramSwift/Build/Products/Debug/Telex.app
```

To see the app's console output, run the binary directly instead of `open`:
```
~/build/TelegramSwift/Build/Products/Debug/Telex.app/Contents/MacOS/Telex
```

## Build and run in Xcode

Open `Telegram-Mac.xcworkspace`, select the **Telegram** scheme (not a
package scheme) and press Run. The team comes from `Secrets.xcconfig`; don't
pick it under Signing & Capabilities, which writes it into the project file.

## First start

The app asks for your Telegram API credentials (`api_id` and `api_hash`) on
first start. Get them at [my.telegram.org](https://my.telegram.org) → API
development tools. The app checks them with Telegram before it saves them.
If Telegram can't be reached (offline, or a network that needs a proxy), you
can "Save anyway"; the next start checks them again.

On every later start the app re-checks the saved values in the background.
Being offline never blocks you. If Telegram rejects the values, the same
popup opens (over Settings when you are logged in) and the app restarts once
you save working ones.

To change the values later, open Settings → API credentials. The app
restarts only when the saved values differ from the ones it runs with.

The Share extension uses the same saved values. If you have not set them
yet, it asks you to open Telex first.

## Notes

- The build number is `CURRENT_PROJECT_VERSION` in the Telegram and
  TelegramShare targets; both must match. Builds no longer change it.
- The submodules show no local changes in `git status`
  (`ignore = dirty` in `.gitmodules`): the build applies
  `patches/<submodule>/` inside them and leaves build output there. Use
  `git -C submodules/<name> status` to see their working tree.
- The app stores its data in the app group folder
  `~/Library/Group Containers/<TeamID>.com.korthane.telex/`. Debug builds use
  its `debug/` subfolder and Release builds use `stable/`, so each needs its
  own login. The API credentials are in `api-credentials.json` at the top of
  that folder, shared by both.
- Release builds now run in the App Sandbox; Debug builds do not.
- The bundle ID changed from `dev.alek.telegram` to `com.korthane.telex`.
  The new ID gets a new, empty app group folder, so log in again. The old
  data is never read; quit every old build and delete it (back up what you
  still need):
  - `~/Library/Group Containers/<TeamID>.dev.alek.telegram` (one per team
    you built with)
  - `~/Library/Application Support/dev.alek.telegram`
  - `~/Library/Containers/dev.alek.telegram`, and the same with
    `.TelegramShare` and `.FocusIntents` appended
  - `~/Library/Caches/dev.alek.telegram`,
    `~/Library/HTTPStorages/dev.alek.telegram`,
    `~/Library/WebKit/dev.alek.telegram`
  - `~/Library/Saved Application State/dev.alek.telegram.savedState`
  - preferences: `defaults delete dev.alek.telegram`
  - camera, microphone and location grants:
    `tccutil reset All dev.alek.telegram`

  macOS may refuse to delete Group Containers and Containers from the
  terminal ("Operation not permitted"); delete them in Finder, or give the
  terminal Full Disk Access. Spotlight items under the old ID stay until
  macOS drops them.
- Before you run a build with a new Telegram core the first time, back up
  the app group folder. The database upgrade on first start (SQLCipher
  4.19) can't be undone, so older builds can't open the data afterwards.
- The passcode is kept by upstream's PasscodeCore in the data protection
  Keychain (shared group `<TeamID>.com.korthane.telex.shared`), separately
  for Debug and Release. The local database key is sealed with a key from
  that Keychain item, so local data depends on it: if the item is lost
  (Keychain reset, another Mac, a copied app group folder), the app offers
  "Quit" or "Log Out and Reset". Reset signs every account out; chats load
  again from the server, secret chats are lost.
- The first start of a build with PasscodeCore moves the old database key
  file (`.tempkeyEncrypted`) to `db-key.v2` and retires the old file. This
  can't be undone: back up the app group folder first. Older builds can't
  open the local data afterwards.
- Touch ID also goes through PasscodeCore. Turning it on or off in the
  passcode settings asks for the passcode. If Touch ID was on in an older
  build, the next unlock with the code turns it on again with one Touch ID
  prompt.
- After the update, open Telex once before sharing: until then the Share
  extension asks you to. The Share extension unlocks with the passcode
  only, never with Touch ID.
- Release sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`, so Release
  bundles carry no `get-task-allow` and can be submitted for
  notarization.
- The app and the Share extension use the Rust MTProto engine and fall back
  to MtProtoKit when it can't run. The app log shows which one runs:
  `Network: Account N: engine rust` or `engine mtProtoKit (...)`. The
  brackets say why: `mtproto_engine_rust_disabled` means the server turned
  Rust off; `factory declined rust` comes with a `[MTProtoRust] declined: ...`
  line giving the reason.
- WEB proxies are not supported on the Mac yet: the app can't add one, and
  the WEB carrier is not hooked up.
- The app refuses to start a second copy, of any build type: copies share
  the app group folder, and two copies on the same database crash. Even a
  Debug build next to a Release one is refused: their accounts are separate,
  but they share files at the top of the app group folder. A second copy
  shows an alert, brings the running one to the front and quits. A `tg://`
  link that started the second copy is lost; open it again in the running
  copy. If the lock can't be taken at all, the app starts anyway and logs
  `Taking the app lock at ... failed`. Builds made before this guard (e.g.
  an old `Telegram.app`) do not check, so delete them.
- Run the FoundationUtils package's unit tests with
  `cd packages/FoundationUtils && swift test`.
- Run the ApiCredentials package's unit tests with
  `cd packages/ApiCredentials && swift test`.
- Run the MacPasscode package's unit tests with
  `cd packages/MacPasscode && swift test`.
- After a build, check that the packages' images (call screen icons) load:
  `swift scripts/check-package-assets.swift ~/build/TelegramSwift/Build/Products/Debug/Telex.app`
  (adjust the path to your build output).
- The app icon is drawn in `images/AppIcon.svg`. After changing it, run
  `bash scripts/render-app-icon.sh` (needs `brew install librsvg`) to
  render the PNGs in `Telegram-Mac/Assets.xcassets/AppIcon.appiconset/`
  and the Share extension's `Icon_TelegramLogin.imageset/`.
- Old copies built with the old bundle ID (`Telegram.app`, or `Telex.app`
  built before the ID change) can't see the new data, but the Share menu
  and Dock may still list them. Delete them
  (`~/build/TelegramSwift/Build/Products/*/Telegram.app`, old `Telex.app`
  copies, `~/Library/Developer/Xcode/DerivedData/Telegram-Mac-*`). Check
  which Share extension is used with
  `pluginkit -m -v -i com.korthane.telex.TelegramShare`. A custom icon
  picked in Settings → Appearance → App Icon replaces the new icon at
  launch; pick Default to see it, and run `killall Dock` if the Dock shows
  a cached icon.
