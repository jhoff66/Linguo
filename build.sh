#!/bin/zsh
# Compila o Linguo e monta o Linguo.app nesta pasta.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
# Binário universal: roda em Apple Silicon e em Intel.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 Sources/Linguo/*.swift -o build/Linguo-$arch
done
lipo -create build/Linguo-arm64 build/Linguo-x86_64 -output build/Linguo

APP="Linguo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Linguo "$APP/Contents/MacOS/Linguo"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Linguo</string>
  <key>CFBundleDisplayName</key><string>Linguo</string>
  <key>CFBundleIdentifier</key><string>com.jhoseferluque.linguo</string>
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
