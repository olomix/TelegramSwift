# Notes for this fork

* The app builds as `Telex.app` with bundle ID `com.korthane.telex`, but
  `PRODUCT_MODULE_NAME` stays `Telegram` and target and scheme names are
  unchanged. Don't rename them.
* `Localizable.strings` is UTF-16LE with a BOM. Edit via
  `iconv` to UTF-8 and back; check with `file` and `plutil -lint`.
* UI strings, including English, come from the downloaded server language
  pack before the bundled strings. App-name menu titles are patched in
  `Telegram-Mac/MMMenuItem.swift`; editing `Localizable.strings` alone is
  not enough.
* The passcode lives in PasscodeCore on the data protection Keychain, which
  needs `patches/telegram-ios/passcodecore-macos-access-group.patch` and
  provisioning profiles; it seals the database key (`db-key.v2`). Never call
  `PasscodeKeychainScope.migrateLegacyItems` or `setupAccountManager`; the
  Share extension uses only `ReadOnlyUnlock`.
* Leave `README.md` as upstream wrote it to keep merge diffs small.
