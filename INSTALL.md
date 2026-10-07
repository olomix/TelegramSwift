# How to Build Telegram for macOS

This fork builds for Apple Silicon only, requires macOS 27 and Xcode 27,
and runs as `dev.alek.telegram`, separate from the official Telegram app.

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
3. Set your Apple team for code signing:
	```
	cp Telegram-Mac/Secrets.example.xcconfig Telegram-Mac/Secrets.xcconfig
	```
   and fill in `DEVELOPMENT_TEAM` (your Apple team ID, shown in Xcode →
   Settings → Accounts). It is required: the app and the Share extension
   share data through an app group, and the group name starts with the team
   ID. Debug and Release builds are both signed with this team as
   "Apple Development". The build signs fine with a paid developer team. A
   free personal team is untested for app groups and may not work. The file
   is git-ignored; never commit it.
4. Build the native libraries (takes 20+ minutes). Repeat after updating
   submodules:
	```
	CMAKE_POLICY_VERSION_MINIMUM=3.5 sh scripts/configure_frameworks.sh
	```
   This also applies the local fixes in `patches/<submodule>/` to the
   submodules.

## Build and run from the console

```
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ~/build/TelegramSwift \
  -allowProvisioningUpdates build

open ~/build/TelegramSwift/Build/Products/Debug/Telegram.app
```

To see the app's console output, run the binary directly instead of `open`:
```
~/build/TelegramSwift/Build/Products/Debug/Telegram.app/Contents/MacOS/Telegram
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
yet, it asks you to open Telegram first.

## Notes

- Each build bumps the build number in `Telegram-Mac/Info.plist` and
  `TelegramShare/Info.plist`. Discard it before committing:
  `git checkout -- Telegram-Mac/Info.plist TelegramShare/Info.plist`
- The app stores its data in the app group folder
  `~/Library/Group Containers/<TeamID>.dev.alek.telegram/`. Debug builds use
  its `debug/` subfolder and Release builds use `stable/`, so each needs its
  own login. The API credentials are in `api-credentials.json` at the top of
  that folder, shared by both.
- Release builds now run in the App Sandbox; Debug builds do not.
- Older builds kept data in
  `~/Library/Application Support/dev.alek.telegram/`. Back up that folder
  before you run this build the first time. Only a Debug build moves it into
  the app group folder on first start (both `debug/` and `stable/`); it
  replaces a folder there only when it holds no `account-*` folder, so a
  login made with this build is kept. The sandbox keeps a Release build from
  reading the old folder. If you use only Release, quit the app and move the
  old `stable/` folder by hand; first delete or rename the `stable/` folder
  in the app group folder if Release already created one:
  ```
  mv ~/Library/Application\ Support/dev.alek.telegram/stable \
    ~/Library/Group\ Containers/<TeamID>.dev.alek.telegram/
  ```
- Run only one copy of the app at a time; copies share the same data folder.
- Run the FoundationUtils package's unit tests with
  `cd packages/FoundationUtils && swift test`.
- Run the ApiCredentials package's unit tests with
  `cd packages/ApiCredentials && swift test`.
- After a build, check that the packages' images (call screen icons) load:
  `swift scripts/check-package-assets.swift ~/build/TelegramSwift/Build/Products/Debug/Telegram.app`
  (adjust the path to your build output).
