#!/bin/bash
# UninstallButler（解除安裝管家）一鍵建置：Universal Binary → .app → .dmg
#   ./build.sh                      本機建置（版本取自 tag 或下方預設值）
#   VERSION=1.2.3 ./build.sh        指定版本（CI 由 tag 傳入）
#   SIGN_ID="UninstallButler Dev" ./build.sh   指定簽章身分（預設自動偵測，找不到就 ad-hoc）
set -euo pipefail
cd "$(dirname "$0")"

APP="UninstallButler"
BUNDLE_ID="com.bowei.uninstallbutler"
DIST="dist"
DEV_KEYCHAIN="$HOME/Library/Keychains/uninstallbutler-dev.keychain-db"
DEV_KEYCHAIN_PASS="$HOME/Library/Application Support/UninstallButler/dev-keychain.pass"

# 版本號：環境變數 VERSION → 乾淨工作樹且 HEAD 正好在 tag 上 → 預設值
TAG_VERSION=""
if git diff-index --quiet HEAD -- 2>/dev/null; then
    TAG_VERSION="$(git describe --tags --exact-match 2>/dev/null || true)"
fi
VERSION="${VERSION:-${TAG_VERSION}}"
VERSION="${VERSION#v}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
echo "▸ 版本 $VERSION (build $BUILD_NUMBER)"

echo "▸ 編譯 Universal Binary (x86_64 + arm64)…"
rm -rf "$DIST"
mkdir -p "$DIST"

if swift build -c release --arch x86_64 --arch arm64 --product "$APP" 2>/dev/null; then
    UNIVERSAL="$(swift build -c release --arch x86_64 --arch arm64 --product "$APP" --show-bin-path)/$APP"
else
    echo "  （合併模式不支援，改用分別編譯 + lipo）"
    swift build -c release --triple x86_64-apple-macosx --product "$APP"
    BIN_X86="$(swift build -c release --triple x86_64-apple-macosx --product "$APP" --show-bin-path)/$APP"
    swift build -c release --triple arm64-apple-macosx --product "$APP"
    BIN_ARM="$(swift build -c release --triple arm64-apple-macosx --product "$APP" --show-bin-path)/$APP"
    UNIVERSAL="$DIST/$APP-universal"
    lipo -create "$BIN_X86" "$BIN_ARM" -output "$UNIVERSAL"
fi
lipo -info "$UNIVERSAL"

echo "▸ 產生圖示…"
ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$DIST/icon_1024.png"
for SZ in 16 32 128 256 512; do
    sips -z $SZ $SZ "$DIST/icon_1024.png" --out "$ICONSET/icon_${SZ}x${SZ}.png" >/dev/null
    DBL=$((SZ * 2))
    sips -z $DBL $DBL "$DIST/icon_1024.png" --out "$ICONSET/icon_${SZ}x${SZ}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$DIST/AppIcon.icns"
mkdir -p docs && cp "$ICONSET/icon_256x256.png" docs/icon.png

echo "▸ 組裝 $APP.app…"
BUNDLE="$DIST/$APP.app"
RES="$BUNDLE/Contents/Resources"
mkdir -p "$BUNDLE/Contents/MacOS" "$RES"
cp "$UNIVERSAL" "$BUNDLE/Contents/MacOS/$APP"
cp "$DIST/AppIcon.icns" "$RES/"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# 本地化顯示名稱（Finder / Dock / 選單列）
declare -a LOCS=("en:Uninstall Butler" "zh-Hant:解除安裝管家" "zh-Hans:卸载管家")
for PAIR in "${LOCS[@]}"; do
    LOC="${PAIR%%:*}"; NAME="${PAIR#*:}"
    mkdir -p "$RES/$LOC.lproj"
    cat > "$RES/$LOC.lproj/InfoPlist.strings" <<EOS
CFBundleDisplayName = "$NAME";
CFBundleName = "$NAME";
EOS
done

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>Uninstall Butler</string>
    <key>CFBundleDisplayName</key><string>Uninstall Butler</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>zh-Hant</string><string>zh-Hans</string></array>
    <key>LSHasLocalizedDisplayName</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Bowei. MIT License.</string>
    <key>NSAppleEventsUsageDescription</key><string>Used only to empty the Trash when you ask for it. / 只在你要求清空垃圾桶時使用。</string>
</dict>
</plist>
PLIST

# 簽章身分：固定的自簽憑證「UninstallButler Dev」讓「完整磁碟取用」授權跨版本有效；找不到就 ad-hoc
if [ -z "${SIGN_ID:-}" ]; then
    if [ -f "$DEV_KEYCHAIN" ] && security find-identity -v -p codesigning "$DEV_KEYCHAIN" 2>/dev/null | grep -q '"UninstallButler Dev"'; then
        SIGN_ID="UninstallButler Dev"
        if [ -f "$DEV_KEYCHAIN_PASS" ]; then security unlock-keychain -p "$(cat "$DEV_KEYCHAIN_PASS")" "$DEV_KEYCHAIN" 2>/dev/null || true; fi
    elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"UninstallButler Dev"'; then
        SIGN_ID="UninstallButler Dev"
    else
        SIGN_ID="-"
    fi
fi
echo "▸ 簽名（identity: ${SIGN_ID}）…"
if [ "$SIGN_ID" = "-" ]; then
    codesign --force --deep -s - "$BUNDLE"
else
    # 固定 designated requirement：identifier + 憑證，讓 TCC 授權在重建後仍然有效
    codesign --force --deep -s "$SIGN_ID" --options runtime --timestamp=none \
        -r="designated => identifier \"$BUNDLE_ID\" and certificate leaf[subject.CN] = \"$SIGN_ID\"" "$BUNDLE"
fi
codesign --verify --deep --strict "$BUNDLE" && echo "  簽名驗證通過"

echo "▸ 製作 DMG…"
STAGE="$DIST/dmg-stage"
mkdir -p "$STAGE"
cp -R "$BUNDLE" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"
hdiutil create -volname "Uninstall Butler" -srcfolder "$STAGE" -format UDZO -ov "$DIST/$APP.dmg" >/dev/null
rm -rf "$STAGE" "$ICONSET" "$DIST/icon_1024.png" "$DIST/$APP-universal"

echo ""
echo "✅ 完成:"
echo "   $DIST/$APP.app   （可直接拖進「應用程式」）"
echo "   $DIST/$APP.dmg   （可分享給其他 Intel / Apple Silicon Mac）"
