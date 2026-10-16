#!/bin/bash
# Render images/AppIcon.svg into the PNGs of AppIcon.appiconset and the
# Share extension's Icon_TelegramLogin image. Run after changing the SVG;
# Contents.json files stay as they are.
set -euo pipefail

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "rsvg-convert not found; install it with: brew install librsvg" >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
svg="$repo_root/images/AppIcon.svg"
assets="$repo_root/Telegram-Mac/Assets.xcassets"
iconset="$assets/AppIcon.appiconset"
login_imageset="$assets/Icon_TelegramLogin.imageset"

# File names must match Contents.json; a -1 file is the 1x slot sharing
# its pixel size with the @2x slot of the size below.
sizes=(
    "Logo_16 16"
    "Logo_32 32"
    "Logo_32-1 32"
    "Logo_64 64"
    "Logo_128 128"
    "Logo_256 256"
    "Logo_256-1 256"
    "Logo_512 512"
    "Logo_512-1 512"
    "Logo_1024 1024"
)

render() {
    local px="$1" out="$2"
    rsvg-convert --width "$px" --height "$px" --format png \
        --output "$out" "$svg"
    echo "${out#"$repo_root"/} ${px}x${px}"
}

for entry in "${sizes[@]}"; do
    read -r name px <<<"$entry"
    render "$px" "$iconset/$name.png"
done

render 80 "$login_imageset/TelegramIcon.png"
render 160 "$login_imageset/TelegramIcon@2x.png"
