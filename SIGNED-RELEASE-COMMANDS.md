# Build, Sign, and Notarize BCU 3.5.0

## 1. Verify identities

```bash
security find-identity -v -p codesigning
security find-identity -v -p basic
```

## 2. Confirm or create the notary profile

To use an existing profile:

```bash
xcrun notarytool history --keychain-profile "BCU-Notary"
```

To create the profile with an app-specific password:

```bash
xcrun notarytool store-credentials "BCU-Notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "PU669FP3N7" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

## 3. Clean, build, sign, package, notarize, and staple

```bash
cd ~/Downloads/Blueprint-Conversion-Utility-3.5.0-Final-UI

xattr -dr com.apple.quarantine .
rm -rf .build .build-artifacts dist
chmod +x build.sh

export BCU_APP_SIGN_IDENTITY="97B3A53FA7FD2C7E0C4FE7705B276BF9E96803DC"
export BCU_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Jarred Wheeler (PU669FP3N7)"
export BCU_NOTARY_PROFILE="BCU-Notary"

./build.sh --version 3.5.0
```

## 4. Verify produced artifacts

```bash
APP="dist/Blueprint Conversion Utility.app"
PKG="dist/Blueprint-Conversion-Utility-3.5.0.pkg"
DMG="dist/Blueprint-Conversion-Utility-3.5.0.dmg"
ZIP="dist/Blueprint-Conversion-Utility-3.5.0-Standalone-App.zip"

plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=4 "$APP"
codesign -dv --verbose=4 "$APP"
spctl --assess --type execute --verbose=4 "$APP"

pkgutil --check-signature "$PKG"
spctl --assess --type install --verbose=4 "$PKG"

xcrun stapler validate "$APP"
xcrun stapler validate "$PKG"
xcrun stapler validate "$DMG"

ls -lh "$APP/Contents/MacOS/BlueprintCreator" "$ZIP" "$PKG" "$DMG"
```

## 5. Optional local test build without notarization

```bash
rm -rf .build .build-artifacts dist
./build.sh --version 3.5.0 --skip-notarization
```
