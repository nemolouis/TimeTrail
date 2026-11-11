#!/bin/bash
# 构建「时迹」TimeTrail.app（只需要 Command Line Tools，不需要 Xcode）
set -euo pipefail
cd "$(dirname "$0")"

BUILD=build
APP="$BUILD/时迹.app"
mkdir -p "$BUILD"

# 某些 Command Line Tools 升级后会残留旧的 usr/include/swift/module.modulemap，
# 与新的 bridging.modulemap 重复定义 SwiftBridging 导致编译失败。
# 这里用 VFS overlay 把旧文件“隐藏”掉，不修改任何系统文件。
EXTRA=()
STALE=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
if [ -f "$STALE" ] && [ -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap ]; then
  : > "$BUILD/empty.modulemap"
  cat > "$BUILD/overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory",
  "name": "/Library/Developer/CommandLineTools/usr/include/swift",
  "contents": [ { "type": "file", "name": "module.modulemap", "external-contents": "$PWD/$BUILD/empty.modulemap" } ] } ] }
EOF
  EXTRA=(-vfsoverlay "$BUILD/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$BUILD/overlay.yaml")
fi

echo "▶︎ 编译中…"
swiftc -parse-as-library -swift-version 5 -O \
  -target "$(uname -m)-apple-macosx14.0" \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  Sources/TimeTrail/*.swift -o "$BUILD/TimeTrail"

echo "▶︎ 打包 .app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/TimeTrail" "$APP/Contents/MacOS/TimeTrail"

# 应用图标：由 Resources/AppIcon-1024.png 生成 icns（PNG 可用 Scripts/make_icon.swift 重新绘制）
if [ -f Resources/AppIcon-1024.png ]; then
  ICONSET="$BUILD/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>TimeTrail</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>local.timetrail.app</string>
  <key>CFBundleName</key><string>时迹</string>
  <key>CFBundleDisplayName</key><string>时迹</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✅ 完成：$APP"
echo "   运行：open \"$APP\""
