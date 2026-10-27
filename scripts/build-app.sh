#!/bin/bash
# 编译并打包成 build/Kura.app
# 用法：scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
# 本机的签名设置（不进代码仓库），例如：KURA_SIGN_IDENTITY="Apple Development: …"
if [ -f scripts/local.env ]; then
  source scripts/local.env
fi
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Kura.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Kura" "$APP/Contents/MacOS/Kura"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
# 默认临时签名。临时签名每次构建都会变，macOS 会把它当成新应用，重新询问“文稿”等文件夹的访问权限；
# 想让授权一直有效，用固定证书签名：KURA_SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh
codesign --force --sign "${KURA_SIGN_IDENTITY:--}" "$APP" >/dev/null
echo "已生成 $APP"
