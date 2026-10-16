#!/bin/bash
# Render images/AppIcon.svg into the PNGs of AppIcon.appiconset.
# Run after changing the SVG; Contents.json stays as it is.
set -euo pipefail

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "rsvg-convert not found; install it with: brew install librsvg" >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
svg="$repo_root/images/AppIcon.svg"
iconset="$repo_root/Telegram-Mac/Assets.xcassets/AppIcon.appiconset"

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

for entry in "${sizes[@]}"; do
    read -r name px <<<"$entry"
    rsvg-convert --width "$px" --height "$px" --format png \
        --output "$iconset/$name.png" "$svg"
    echo "$name.png ${px}x${px}"
done
