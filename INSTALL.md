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
3. Add your Telegram API credentials. Create an app at
   [my.telegram.org](https://my.telegram.org) → API development tools, then:
	```
	cp Telegram-Mac/Secrets.example.xcconfig Telegram-Mac/Secrets.xcconfig
	```
   and fill in `TG_API_ID`, `TG_API_HASH` and `DEVELOPMENT_TEAM` (your Apple
   team ID, shown in Xcode → Settings → Accounts; a free personal team
   works). The file is git-ignored; never commit it. Without it the app
   builds but stops at launch.
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

## Notes

- Each build bumps the build number in `Telegram-Mac/Info.plist` and
  `TelegramShare/Info.plist`. Discard it before committing:
  `git checkout -- Telegram-Mac/Info.plist TelegramShare/Info.plist`
- Debug builds store data in
  `~/Library/Application Support/dev.alek.telegram/debug/`; Release builds use
  `stable/`, so each needs its own login.
- Run only one copy of the app at a time; copies share the same data folder.
- Run the FoundationUtils package's unit tests with
  `cd packages/FoundationUtils && swift test`.
