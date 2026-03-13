#!/bin/bash
set -euo pipefail

APP_NAME="Claudex"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ICON_FILE="${HOME}/Downloads/Claudex.icon"

echo "==> Building ${APP_NAME} (release)..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

# Copy binary
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"

# Compile .icon file using actool (Icon Composer format)
echo "==> Compiling app icon..."
ICON_TMP=$(mktemp -d)
RESOURCES_ABS=$(cd "${RESOURCES}" && pwd)
if xcrun actool \
    --compile "${RESOURCES_ABS}" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon "Claudex" \
    --include-all-app-icons \
    --output-partial-info-plist "${ICON_TMP}/Icon-Info.plist" \
    "${ICON_FILE}" 2>&1 | grep -q "output-files"; then
    echo "    Icon compiled via actool"
else
    echo "    actool failed, falling back to .icns"
    # Fallback: use the .icns we generated earlier
    if [ -f "AppIcon.icns" ]; then
        cp AppIcon.icns "${RESOURCES}/AppIcon.icns"
    fi
fi
rm -rf "${ICON_TMP}"

# Write Info.plist (CFBundleIconName for Assets.car, CFBundleIconFile for .icns fallback)
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Claudex</string>
    <key>CFBundleDisplayName</key>
    <string>Claudex</string>
    <key>CFBundleIdentifier</key>
    <string>com.claudex.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Claudex</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>Claudex</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Claudex needs access to Terminal.app to discover and import your existing terminal sessions.</string>
</dict>
</plist>
PLIST

# Write entitlements (sandbox disabled for PTY access)
cat > /tmp/Claudex.entitlements << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
ENTITLEMENTS

# Codesign
echo "==> Codesigning..."
codesign --force --sign - --entitlements /tmp/Claudex.entitlements "${APP_BUNDLE}"

# Install claudex-open CLI tool to user-local bin
echo "==> Installing claudex-open..."
mkdir -p "${HOME}/.local/bin"
cp claudex-open "${HOME}/.local/bin/claudex-open"
chmod +x "${HOME}/.local/bin/claudex-open"

# Install to /Applications
echo "==> Installing to /Applications..."
rm -rf "/Applications/${APP_BUNDLE}"
cp -R "${APP_BUNDLE}" "/Applications/${APP_BUNDLE}"

echo "==> Done! ${APP_BUNDLE} installed to /Applications."
echo "    Run with: open /Applications/${APP_BUNDLE}"
echo "    CLI:  claudex-open /path/to/file"
