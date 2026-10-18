#!/bin/bash
# Build a Developer ID signed, notarized Telex.app and zip it.
#
# Usage: scripts/release.sh [--no-notarize | --resume <submission-id>]
#
# --resume finishes an earlier run whose notarization wait failed: it skips
# the build and waits for, staples and zips the already exported app.
#
# Needs the Release signing lines in Telegram-Mac/Secrets.xcconfig and, for
# notarization, credentials saved once with
#   xcrun notarytool store-credentials <profile>
# with <profile> set as TELEX_NOTARY_PROFILE in Secrets.xcconfig or the
# environment (default telex-notary). Output goes to build/release/
# (override with TELEX_RELEASE_DIR).

set -euo pipefail

notarize=1
resume_id=""
usage() { echo "usage: $0 [--no-notarize | --resume <submission-id>]" >&2; exit 2; }
case "${1:-}" in
    "") ;;
    --no-notarize) notarize=0 ;;
    --resume) resume_id="${2:-}"; [[ -n "$resume_id" ]] || usage ;;
    *) usage ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
secrets="$root/Telegram-Mac/Secrets.xcconfig"
out="${TELEX_RELEASE_DIR:-$root/build/release}"
# Separate from the Debug build folder so the two can run side by side.
derived="${TELEX_DERIVED_DATA:-$HOME/build/TelegramSwift-release}"

app_id="com.korthane.telex"
share_id="com.korthane.telex.TelegramShare"

fail() { echo "error: $*" >&2; exit 1; }

secret() {
    [[ -f "$secrets" ]] || fail "missing $secrets (see INSTALL.md)"
    sed -n -E "s|^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$|\\1|p" \
        "$secrets" | tail -n 1
}

team="$(secret DEVELOPMENT_TEAM)"
sign_style="$(secret TELEX_RELEASE_SIGN_STYLE)"
identity="$(secret TELEX_RELEASE_SIGN_IDENTITY)"
app_profile="$(secret TELEX_APP_PROFILE)"
share_profile="$(secret TELEX_SHARE_PROFILE)"
notary_profile="${TELEX_NOTARY_PROFILE:-$(secret TELEX_NOTARY_PROFILE)}"
notary_profile="${notary_profile:-telex-notary}"

[[ -n "$team" ]] || fail "DEVELOPMENT_TEAM is not set in $secrets"
# Notarization accepts only Developer ID builds.
[[ "$sign_style" == "Manual" && "$identity" == "Developer ID Application" \
   && -n "$app_profile" && -n "$share_profile" ]] \
    || fail "set the Developer ID lines from Secrets.example.xcconfig in $secrets"

if (( notarize )); then
    xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 \
        || fail "no notary credentials '$notary_profile'; run: xcrun notarytool store-credentials $notary_profile"
fi

archive="$out/Telex.xcarchive"
export_dir="$out/export"
app="$export_dir/Telex.app"

build_app() {
    rm -rf "$out"
    mkdir -p "$out"

    echo "==> Archiving"
    xcodebuild archive \
        -workspace "$root/Telegram-Mac.xcworkspace" \
        -scheme Release -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$derived" \
        -archivePath "$archive" \
        -quiet

    echo "==> Exporting with Developer ID"
    options="$out/ExportOptions.plist"
    cat > "$options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$team</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>$identity</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$app_id</key><string>$app_profile</string>
        <key>$share_id</key><string>$share_profile</string>
    </dict>
</dict>
</plist>
EOF
    xcodebuild -exportArchive -archivePath "$archive" \
        -exportOptionsPlist "$options" -exportPath "$export_dir" -quiet

    echo "==> Checking the signature"
    codesign --verify --deep --strict "$app"
    for bundle in "$app" "$app/Contents/PlugIns/TelegramShare.appex"; do
        [[ -d "$bundle" ]] || fail "missing $bundle"
        # Capture first: grep -q closing the pipe early fails it under pipefail.
        entitlements="$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null)"
        details="$(codesign -d --verbose=2 "$bundle" 2>&1)"
        if grep -q "get-task-allow" <<< "$entitlements"; then
            fail "$bundle carries get-task-allow; notarization rejects it"
        fi
        grep -q "flags=.*runtime" <<< "$details" \
            || fail "$bundle lacks the hardened runtime"
    done
}

if [[ -n "$resume_id" ]]; then
    [[ -d "$app" ]] || fail "no exported app at $app to resume"
else
    build_app
fi

plist="$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
zip="$out/Telex-$version-$build.zip"

if (( notarize )); then
    result="$out/notary.json"
    id="$resume_id"
    if [[ -z "$id" ]]; then
        echo "==> Uploading for notarization"
        upload="$out/upload.zip"
        ditto -c -k --keepParent "$app" "$upload"
        xcrun notarytool submit "$upload" --keychain-profile "$notary_profile" \
            --output-format json > "$result"
        id="$(plutil -extract id raw -o - "$result")"
        rm "$upload"
    fi

    echo "==> Waiting for Apple (usually a few minutes), submission $id"
    # Long waits often hit network timeouts; the submission itself goes on.
    status=""
    for attempt in $(seq 1 20); do
        xcrun notarytool wait "$id" --keychain-profile "$notary_profile" \
            --timeout 30m >/dev/null 2>&1 || true
        if xcrun notarytool info "$id" --keychain-profile "$notary_profile" \
            --output-format json > "$result" 2>/dev/null; then
            status="$(plutil -extract status raw -o - "$result")"
            [[ "$status" != "In Progress" ]] && break
        fi
        echo "    still waiting (attempt $attempt of 20)"
        sleep 30
    done
    if [[ "$status" != "Accepted" ]]; then
        xcrun notarytool log "$id" --keychain-profile "$notary_profile" \
            "$out/notary-log.json" || true
        fail "notarization status '${status:-unknown}'; see $out/notary-log.json, or resume with: $0 --resume $id"
    fi

    echo "==> Stapling"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
else
    zip="$out/Telex-$version-$build-unnotarized.zip"
fi

ditto -c -k --keepParent "$app" "$zip"
echo "==> Done: $zip"
