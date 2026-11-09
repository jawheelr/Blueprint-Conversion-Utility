#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

[[ "$(id -u)" -ne 0 ]] || { echo "ERROR: Do not run this build with sudo." >&2; exit 1; }

VERSION="${APP_VERSION:-3.5.0}"
ARCH="${BUILD_ARCH:-$(uname -m)}"
APP_IDENTITY="${BCU_APP_SIGN_IDENTITY:-}"
INSTALLER_IDENTITY="${BCU_INSTALLER_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${BCU_NOTARY_PROFILE:-}"
NOTARIZE=1

usage() {
  cat <<EOF
Usage: ./build.sh [options]
  --version <version>          Release version (default: $VERSION)
  --arch <arm64|x86_64>        Build architecture (default: $ARCH)
  --sign-app <identity>        Developer ID Application identity or fingerprint
  --sign-installer <identity>  Developer ID Installer identity
  --notary-profile <name>      notarytool Keychain profile
  --skip-notarization          Produce test artifacts without notarization
  --help                       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --sign-app) APP_IDENTITY="$2"; shift 2 ;;
    --sign-installer) INSTALLER_IDENTITY="$2"; shift 2 ;;
    --notary-profile) NOTARY_PROFILE="$2"; shift 2 ;;
    --skip-notarization) NOTARIZE=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$ARCH" == "arm64" || "$ARCH" == "x86_64" ]] || { echo "ERROR: Unsupported architecture: $ARCH" >&2; exit 2; }
for tool in swift go codesign pkgbuild hdiutil ditto plutil; do command -v "$tool" >/dev/null || { echo "ERROR: Required tool not found: $tool" >&2; exit 1; }; done
[[ -f Package.swift ]] || { echo "ERROR: Package.swift is missing." >&2; exit 1; }
[[ -f Info.plist ]] || { echo "ERROR: Info.plist is missing." >&2; exit 1; }
[[ -f Resources/AppleSchema/apple-device-management-catalog.json ]] || { echo "ERROR: Apple schema catalog is missing." >&2; exit 1; }
[[ -f Resources/AppleSchema/apple-device-management-index.json ]] || { echo "ERROR: Apple schema index is missing." >&2; exit 1; }
# Archived jamf-cli source can omit generated/internal packages. Helper discovery
# below only compiles it when its required local package graph is complete.

APP_NAME="Blueprint Conversion Utility"
FINAL_APP="dist/$APP_NAME.app"
PKG="dist/Blueprint-Conversion-Utility-$VERSION.pkg"
DMG="dist/Blueprint-Conversion-Utility-$VERSION.dmg"
STANDALONE_ZIP="dist/Blueprint-Conversion-Utility-$VERSION-Standalone-App.zip"
BUILD_DIR=".build/release-$ARCH"
ARTIFACTS=".build-artifacts"
STAGE_APP="$ARTIFACTS/stage/$APP_NAME.app"
GO_BIN_DIR="$ARTIFACTS/go-bin"
PKGROOT="$ARTIFACTS/pkgroot"
DMGROOT="$ARTIFACTS/dmg"
LOG="$ARTIFACTS/build-$VERSION.log"

rm -rf "$BUILD_DIR" "$ARTIFACTS" dist
mkdir -p "$ARTIFACTS" "$GO_BIN_DIR" "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources/bin" "$STAGE_APP/Contents/Resources/AppleSchema" dist
exec > >(tee "$LOG") 2>&1

fail() {
  local code=$?
  echo
  echo "BUILD FAILED (exit $code). No partial application was published to dist/."
  echo "Build log: $LOG"
  exit "$code"
}
trap fail ERR

echo "Building BCU $VERSION for $ARCH"
echo "Swift: $(swift --version | head -1)"
echo "Go: $(go version)"

echo "==> Building Swift products"
swift build -c release --arch "$ARCH" --build-path "$BUILD_DIR"
SWIFT_BIN="$(swift build -c release --arch "$ARCH" --build-path "$BUILD_DIR" --show-bin-path)"
[[ -x "$SWIFT_BIN/BlueprintCreator" ]] || { echo "ERROR: BlueprintCreator was not produced at $SWIFT_BIN/BlueprintCreator" >&2; find "$BUILD_DIR" -type f -name BlueprintCreator -print >&2 || true; false; }
[[ -x "$SWIFT_BIN/bcu" ]] || { echo "ERROR: bcu was not produced at $SWIFT_BIN/bcu" >&2; find "$BUILD_DIR" -type f -name bcu -print >&2 || true; false; }

case "$(file -b "$SWIFT_BIN/BlueprintCreator")" in
  *"$ARCH"*) ;;
  *) echo "ERROR: BlueprintCreator does not contain the requested architecture $ARCH: $(file -b "$SWIFT_BIN/BlueprintCreator")" >&2; false ;;
esac

echo "==> Resolving jamf-cli helper products"
find_helper() {
  local name="$1"
  local candidate
  for candidate in "Resources/bin/$name" "Vendor/bin/$ARCH/$name" "$HOME/.local/bin/$name" "$(command -v "$name" 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -f "$candidate" && -x "$candidate" ]]; then printf '%s' "$candidate"; return 0; fi
  done
  return 1
}
JAMF_SOURCE_COMPLETE=1
for package in config gateway privileges output xmlconv keychain platform registry exitcode cooldown spinner httptransport; do
  [[ -d "Vendor/jamf-cli/internal/$package" ]] || JAMF_SOURCE_COMPLETE=0
done
JAMF_CLI_SOURCE="$(find_helper jamf-cli || true)"
CONVERTER_SOURCE="$(find_helper blueprint-profile-convert || true)"
if [[ -z "$JAMF_CLI_SOURCE" || -z "$CONVERTER_SOURCE" ]]; then
  if [[ "$JAMF_SOURCE_COMPLETE" -eq 1 && -f Vendor/jamf-cli/go.mod ]]; then
    echo "Complete vendored jamf-cli source detected; compiling helpers."
    pushd Vendor/jamf-cli >/dev/null
    GOOS=darwin GOARCH="$ARCH" CGO_ENABLED=0 go build -mod=mod -trimpath -ldflags="-s -w" -o "$OLDPWD/$GO_BIN_DIR/jamf-cli" ./cmd/jamf-cli
    GOOS=darwin GOARCH="$ARCH" CGO_ENABLED=0 go build -mod=mod -trimpath -ldflags="-s -w" -o "$OLDPWD/$GO_BIN_DIR/blueprint-profile-convert" ./cmd/blueprint-profile-convert
    popd >/dev/null
    JAMF_CLI_SOURCE="$GO_BIN_DIR/jamf-cli"; CONVERTER_SOURCE="$GO_BIN_DIR/blueprint-profile-convert"
  else
    echo "WARNING: The included jamf-cli source snapshot is incomplete and cannot be compiled."
    echo "WARNING: Building a runnable BCU app without bundled helpers."
    echo "WARNING: Put prebuilt jamf-cli and blueprint-profile-convert in Resources/bin or ~/.local/bin and rebuild to enable helper-backed operations."
  fi
fi
[[ -z "$JAMF_CLI_SOURCE" ]] || cp "$JAMF_CLI_SOURCE" "$STAGE_APP/Contents/Resources/bin/jamf-cli"
[[ -z "$CONVERTER_SOURCE" ]] || cp "$CONVERTER_SOURCE" "$STAGE_APP/Contents/Resources/bin/blueprint-profile-convert"

echo "==> Assembling staged application bundle"
cp "$SWIFT_BIN/BlueprintCreator" "$STAGE_APP/Contents/MacOS/BlueprintCreator"
cp "$SWIFT_BIN/bcu" "$STAGE_APP/Contents/Resources/bin/bcu"
cp Info.plist "$STAGE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$STAGE_APP/Contents/Info.plist"
plutil -lint "$STAGE_APP/Contents/Info.plist"
cp Resources/AppMark.png "$STAGE_APP/Contents/Resources/AppMark.png"
cp Resources/AppleSchema/*.json "$STAGE_APP/Contents/Resources/AppleSchema/"
if command -v iconutil >/dev/null && [[ -d Resources/AppIcon.iconset ]]; then
  iconutil -c icns Resources/AppIcon.iconset -o "$STAGE_APP/Contents/Resources/AppIcon.icns"
fi
chmod 755 "$STAGE_APP/Contents/MacOS/BlueprintCreator" "$STAGE_APP/Contents/Resources/bin/bcu"
find "$STAGE_APP/Contents/Resources/bin" -type f -maxdepth 1 -exec chmod 755 {} +

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$STAGE_APP/Contents/Info.plist")" == "BlueprintCreator" ]] || { echo "ERROR: CFBundleExecutable does not match BlueprintCreator." >&2; false; }
[[ -x "$STAGE_APP/Contents/MacOS/BlueprintCreator" ]] || { echo "ERROR: Main app executable is absent from the staged bundle." >&2; false; }
[[ -f "$STAGE_APP/Contents/Resources/AppleSchema/apple-device-management-catalog.json" ]] || { echo "ERROR: Schema catalog is absent from the staged bundle." >&2; false; }

echo "==> Signing application bundle"
if [[ -n "$APP_IDENTITY" ]]; then
  while IFS= read -r executable; do codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$executable"; done < <(find "$STAGE_APP/Contents/Resources/bin" -type f -maxdepth 1 -print)
  codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$STAGE_APP/Contents/MacOS/BlueprintCreator"
  codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$STAGE_APP"
else
  while IFS= read -r executable; do codesign --force --sign - "$executable"; done < <(find "$STAGE_APP/Contents/Resources/bin" -type f -maxdepth 1 -print)
  codesign --force --sign - "$STAGE_APP/Contents/MacOS/BlueprintCreator"
  codesign --force --sign - "$STAGE_APP"
fi
codesign --verify --deep --strict --verbose=4 "$STAGE_APP"

# Publish only after the complete staged app has passed bundle and signature validation.
ditto "$STAGE_APP" "$FINAL_APP"
[[ -x "$FINAL_APP/Contents/MacOS/BlueprintCreator" ]] || { echo "ERROR: Published standalone app is incomplete." >&2; false; }

echo "==> Creating standalone app ZIP"
ditto -c -k --sequesterRsrc --keepParent "$FINAL_APP" "$STANDALONE_ZIP"

echo "==> Creating installer PKG"
mkdir -p "$PKGROOT/Applications" "$PKGROOT/usr/local/bin"
ditto "$FINAL_APP" "$PKGROOT/Applications/$APP_NAME.app"
ln -s "/Applications/$APP_NAME.app/Contents/Resources/bin/bcu" "$PKGROOT/usr/local/bin/bcu"
PKGBUILD_ARGS=(--root "$PKGROOT" --install-location / --identifier com.jawheelr.blueprintcreator --version "$VERSION")
if [[ -n "$INSTALLER_IDENTITY" ]]; then PKGBUILD_ARGS+=(--sign "$INSTALLER_IDENTITY"); fi
pkgbuild "${PKGBUILD_ARGS[@]}" "$PKG"
[[ -f "$PKG" ]] || { echo "ERROR: PKG was not produced." >&2; false; }
if [[ -n "$INSTALLER_IDENTITY" ]]; then pkgutil --check-signature "$PKG"; fi

if [[ "$NOTARIZE" -eq 1 && -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG"
  xcrun stapler validate "$PKG"
fi

echo "==> Creating DMG"
mkdir -p "$DMGROOT"
ditto "$FINAL_APP" "$DMGROOT/$APP_NAME.app"
cp "$PKG" "$DMGROOT/"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$DMGROOT" -ov -format UDZO "$DMG"
[[ -f "$DMG" ]] || { echo "ERROR: DMG was not produced." >&2; false; }

if [[ "$NOTARIZE" -eq 1 && -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

if [[ -n "$APP_IDENTITY" ]]; then spctl --assess --type execute --verbose=4 "$FINAL_APP"; fi
if [[ -n "$INSTALLER_IDENTITY" ]]; then spctl --assess --type install --verbose=4 "$PKG"; fi

trap - ERR
printf '\nBUILD COMPLETE\n  Standalone app: %s\n  Standalone ZIP: %s\n  Installer PKG:  %s\n  Disk image DMG: %s\n  Build log:      %s\n' "$FINAL_APP" "$STANDALONE_ZIP" "$PKG" "$DMG" "$LOG"
ls -lh "$FINAL_APP/Contents/MacOS/BlueprintCreator" "$STANDALONE_ZIP" "$PKG" "$DMG"
