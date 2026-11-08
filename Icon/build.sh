#!/bin/zsh
# Regenerate the Citlla E510 app icon set.
# Requires: macOS, swift, sips, iconutil.
set -euo pipefail
cd "$(dirname "$0")"

swift make-icon.swift

rm -rf icon.iconset
mkdir -p icon.iconset

emit() {
  sips -z "$1" "$1" icon-1024.png --out "icon.iconset/$2" >/dev/null
}

emit 16   icon_16x16.png
emit 32   icon_16x16@2x.png
emit 32   icon_32x32.png
emit 64   icon_32x32@2x.png
emit 128  icon_128x128.png
emit 256  icon_128x128@2x.png
emit 256  icon_256x256.png
emit 512  icon_256x256@2x.png
emit 512  icon_512x512.png
cp        icon-1024.png icon.iconset/icon_512x512@2x.png

iconutil -c icns icon.iconset -o citlla-e510.icns

for s in 512 256 128 64 32 16; do
  sips -z $s $s icon-1024.png --out "icon-${s}.png" >/dev/null
done

cp icon.iconset/*.png ../CitllaE510/Assets.xcassets/AppIcon.appiconset/

echo "built: citlla-e510.icns, png previews, and AppIcon assets"
