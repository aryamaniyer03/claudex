#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./bundle.sh [--install-app] [--install-cli] [--install]

Builds a release app bundle in the current directory.

Options:
  --install-app  Copy the built app to /Applications (or $APP_INSTALL_DIR)
  --install-cli  Copy claudex-open to ~/.local/bin (or $CLI_INSTALL_DIR)
  --install      Install both the app and the CLI helper
  --help         Show this help text
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Claudex"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
APP_INSTALL_DIR="${APP_INSTALL_DIR:-/Applications}"
CLI_INSTALL_DIR="${CLI_INSTALL_DIR:-${HOME}/.local/bin}"

INSTALL_APP=false
INSTALL_CLI=false

for arg in "$@"; do
    case "${arg}" in
        --install-app)
            INSTALL_APP=true
            ;;
        --install-cli)
            INSTALL_CLI=true
            ;;
        --install)
            INSTALL_APP=true
            INSTALL_CLI=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: ${arg}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

echo "==> Building ${APP_NAME} (release)..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

# Copy binary
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"

# Copy SPM resource bundle (contains logo/icon PNGs)
# Detect architecture automatically instead of hardcoding arm64
RESOURCE_BUNDLE=""
for arch_dir in .build/arm64-apple-macosx/release .build/x86_64-apple-macosx/release .build/release; do
    if [ -d "${arch_dir}/Claudex_Claudex.bundle" ]; then
        RESOURCE_BUNDLE="${arch_dir}/Claudex_Claudex.bundle"
        break
    fi
done
if [ -n "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${RESOURCES}/Claudex_Claudex.bundle"
    echo "    Copied resource bundle from ${RESOURCE_BUNDLE}"
else
    echo "    WARNING: SPM resource bundle not found, logo/icon will be missing"
fi

# Compile app icon from .icon file (Icon Composer format)
# Produces Assets.car (Liquid Glass) + Claudex.icns (legacy fallback)
echo "==> Compiling app icon..."
ICON_TMP=$(mktemp -d)
if xcrun actool "${SCRIPT_DIR}/Claudex.icon" \
    --compile "${RESOURCES}" \
    --output-format human-readable-text \
    --notices --warnings --errors \
    --output-partial-info-plist "${ICON_TMP}/Icon-Info.plist" \
    --app-icon Claudex \
    --include-all-app-icons \
    --enable-on-demand-resources NO \
    --development-region en \
    --target-device mac \
    --minimum-deployment-target 14.0 \
    --platform macosx 2>&1 | head -5; then
    echo "    Icon compiled (Assets.car + Claudex.icns)"
else
    echo "    actool failed, falling back to AppIcon.icns"
    cp "${SCRIPT_DIR}/AppIcon.icns" "${RESOURCES}/AppIcon.icns"
fi
rm -rf "${ICON_TMP}"

# Write Info.plist
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
    <string>Claudex</string>
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

if ${INSTALL_CLI}; then
    echo "==> Installing claudex-open..."
    mkdir -p "${CLI_INSTALL_DIR}"
    cp claudex-open "${CLI_INSTALL_DIR}/claudex-open"
    chmod +x "${CLI_INSTALL_DIR}/claudex-open"
    echo "    Installed CLI to ${CLI_INSTALL_DIR}/claudex-open"
fi

if ${INSTALL_APP}; then
    echo "==> Installing app..."
    if [ ! -d "${APP_INSTALL_DIR}" ]; then
        echo "ERROR: App install directory does not exist: ${APP_INSTALL_DIR}" >&2
        exit 1
    fi
    if [ ! -w "${APP_INSTALL_DIR}" ]; then
        echo "ERROR: No write access to ${APP_INSTALL_DIR}. Re-run with a writable APP_INSTALL_DIR or install manually." >&2
        exit 1
    fi
    rm -rf "${APP_INSTALL_DIR}/${APP_BUNDLE}"
    cp -R "${APP_BUNDLE}" "${APP_INSTALL_DIR}/${APP_BUNDLE}"
    echo "    Installed app to ${APP_INSTALL_DIR}/${APP_BUNDLE}"
fi

echo "==> Done! Built ${APP_BUNDLE} in ${SCRIPT_DIR}/${APP_BUNDLE}"
if ! ${INSTALL_APP} && ! ${INSTALL_CLI}; then
    echo "    Local build only. Use --install-app and/or --install-cli to install artifacts."
fi
echo "    Run with: open ${SCRIPT_DIR}/${APP_BUNDLE}"
