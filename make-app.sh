#!/bin/bash
# Builds BrowserProxy.app from the SwiftPM executable.
#
#   ./make-app.sh            build the .app in this directory (not registered)
#   ./make-app.sh install    build, install to /Applications, register with
#                            LaunchServices so it can be picked as the default browser
#
# Only the installed copy is registered on purpose: registering both this build
# and the /Applications copy under the same bundle id makes LaunchServices
# ambiguous about which one to launch.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="BrowserProxy"
BUNDLE_ID="de.efec.BrowserProxy"
CONFIG="release"
INSTALL_DIR="/Applications"
# Stage the bundle under .build so a stray copy never sits in the project root:
# LaunchServices auto-registers any app bundle it notices, and two registered
# copies with the same bundle id make it ambiguous which one macOS launches.
STAGE_DIR=".build/bundle"
APP_DIR="${STAGE_DIR}/${APP_NAME}.app"
DO_INSTALL="no"
[[ "${1:-}" == "install" ]] && DO_INSTALL="yes"

echo "==> swift build (${CONFIG})"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: built binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "==> assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${STAGE_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Optional icon.
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
  ICON_KEY='<key>CFBundleIconFile</key><string>AppIcon</string>'
else
  ICON_KEY=''
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    ${ICON_KEY}
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>Web site URL</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>http</string>
                <string>https</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Default</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "==> ad-hoc code signing"
codesign --force --sign - "${APP_DIR}"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ "${DO_INSTALL}" == "yes" ]]; then
  TARGET="${INSTALL_DIR}/${APP_NAME}.app"
  echo "==> installing to ${TARGET}"
  # Quit a running instance so the bundle can be replaced cleanly.
  osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
  rm -rf "${TARGET}"
  cp -R "${APP_DIR}" "${TARGET}"
  xattr -dr com.apple.quarantine "${TARGET}" 2>/dev/null || true

  echo "==> registering ${TARGET} with LaunchServices"
  # Drop the local build's registration so only the installed copy is a handler.
  "${LSREGISTER}" -u "$(pwd)/${APP_DIR}" 2>/dev/null || true
  "${LSREGISTER}" -f "${TARGET}"

  echo "==> installed: ${TARGET}"
  echo "    Set it as default: System Settings > Desktop & Dock > Default web browser"
else
  echo "==> built: $(pwd)/${APP_DIR} (not registered; use './make-app.sh install')"
fi
