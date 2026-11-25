#!/usr/bin/env bash
# Build MacFans (Release) and package as DMG
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacFans"
SCHEME="MacFans"
PROJECT="MacFans.xcodeproj"
CONFIG="Release"
DERIVED="${ROOT}/build/DerivedData"
STAGE="${ROOT}/build/dmg-stage"
OUT_DIR="${ROOT}/build/dist"

VERSION="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/MacFans/Info.plist" 2>/dev/null || echo "1.0.0"
)"
BUILD="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${ROOT}/MacFans/Info.plist" 2>/dev/null || echo "1"
)"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${OUT_DIR}/${DMG_NAME}"
VOL_NAME="${APP_NAME} ${VERSION}"

echo "==> Cleaning old artifacts"
rm -rf "${STAGE}" "${DERIVED}/Build/Products/${CONFIG}"
mkdir -p "${STAGE}" "${OUT_DIR}"

echo "==> Building ${CONFIG} (${APP_NAME} ${VERSION} build ${BUILD})"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath "${DERIVED}" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  clean build \
  | /usr/bin/sed -E 's/^/    /'

APP_SRC="${DERIVED}/Build/Products/${CONFIG}/${APP_NAME}.app"
if [[ ! -d "${APP_SRC}" ]]; then
  echo "Error: app not found at ${APP_SRC}" >&2
  exit 1
fi

echo "==> Staging .app"
ditto "${APP_SRC}" "${STAGE}/${APP_NAME}.app"
ln -sf /Applications "${STAGE}/Applications"

cat > "${STAGE}/README.txt" <<EOF
MacFans ${VERSION}

1. Drag MacFans.app into the Applications folder
2. If Gatekeeper blocks it: System Settings -> Privacy & Security -> Open Anyway
3. Launch the app and click "Install Helper" once (admin password)
4. All preset / sensor-curve features are free

Uninstall helper:
  sudo launchctl bootout system /Library/LaunchDaemons/com.macfans.helper.plist
  sudo rm -f /Library/LaunchDaemons/com.macfans.helper.plist \\
    /Library/PrivilegedHelperTools/com.macfans.FanWriteTool
EOF

echo "==> Creating DMG -> ${DMG_PATH}"
rm -f "${DMG_PATH}" "${OUT_DIR}/${APP_NAME}-temp.dmg"

hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE}" \
  -ov \
  -format UDRW \
  "${OUT_DIR}/${APP_NAME}-temp.dmg" >/dev/null

hdiutil convert \
  "${OUT_DIR}/${APP_NAME}-temp.dmg" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${DMG_PATH}" >/dev/null

rm -f "${OUT_DIR}/${APP_NAME}-temp.dmg"
rm -rf "${STAGE}"

SIZE="$(du -h "${DMG_PATH}" | awk '{print $1}')"
echo ""
echo "Done: ${DMG_PATH} (${SIZE})"
echo "Checksum:"
shasum -a 256 "${DMG_PATH}" | awk '{print "  SHA-256:", $1}'
ls -lh "${DMG_PATH}"
