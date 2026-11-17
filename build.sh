#!/bin/bash
# 在 Mac 上打 Kiki 桌宠：./build.sh  → out/KikiPet.app（本机临时签名，自己用）
# 画面在 Kiki 后台（/pet.html），这里只编外壳，所以 Kiki 要先开着（本机或 Kiki.app 连着的那台）。
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-out}"
APP="$OUT/KikiPet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target "$(uname -m)-apple-macos13.5" main.swift -o "$APP/Contents/MacOS/KikiPet"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "打好了：$APP"
echo "试一下：open \"$APP\"   （装到应用程序：cp -R \"$APP\" /Applications/）"
