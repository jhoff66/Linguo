#!/bin/zsh
# Compila o Linguo e monta o Linguo.app nesta pasta.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build

# `./build.sh icon` redesenha o Resources/AppIcon.icns a partir do Tools/make-icon.swift.
if [[ "${1:-}" == "icon" ]]; then
  swiftc -O Tools/make-icon.swift -o build/make-icon
  build/make-icon build/icon.png
  SET="build/AppIcon.iconset"
  rm -rf "$SET" && mkdir -p "$SET" Resources
  for px in 16 32 128 256 512; do
    sips -z $px $px build/icon.png --out "$SET/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) build/icon.png --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o Resources/AppIcon.icns
  echo "Ícone: $PWD/Resources/AppIcon.icns"
  exit 0
fi
# Binário universal: roda em Apple Silicon e em Intel.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 Sources/Linguo/*.swift -o build/Linguo-$arch
done
lipo -create build/Linguo-arm64 build/Linguo-x86_64 -output build/Linguo

APP="Linguo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Linguo "$APP/Contents/MacOS/Linguo"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Linguo</string>
  <key>CFBundleDisplayName</key><string>Linguo</string>
  <key>CFBundleIdentifier</key><string>com.jhoseferluque.linguo</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>Linguo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Assina com o certificado Apple Development, se houver (senão, assinatura local): com certificado, a permissão de Acessibilidade sobrevive a cada novo build.
IDENTITY=$(security find-identity -p codesigning -v | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Pronto: $PWD/$APP"
