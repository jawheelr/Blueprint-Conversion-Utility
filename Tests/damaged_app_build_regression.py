from pathlib import Path
s=Path('build.sh').read_text()
checks={
'staged bundle':'STAGE_APP=' in s,
'no early published app':'mkdir -p "$ARTIFACTS" "$GO_BIN_DIR" "$STAGE_APP/Contents/MacOS"' in s,
'publish after verification':'ditto "$STAGE_APP" "$FINAL_APP"' in s,
'main executable check':'Main app executable is absent from the staged bundle' in s,
'plist executable check':'CFBundleExecutable does not match BlueprintCreator' in s,
'plist lint':'plutil -lint' in s,
'architecture check':'does not contain the requested architecture' in s,
'go modules':'go build -mod=mod' in s and 'JAMF_SOURCE_COMPLETE' in s,
'no partial dist':'No partial application was published to dist/' in s,
'stage signature':'codesign --verify --deep --strict --verbose=4 "$STAGE_APP"' in s,
'published app check':'Published standalone app is incomplete' in s,
'artifacts after valid app':s.index('ditto "$STAGE_APP" "$FINAL_APP"') < s.index('Creating installer PKG'),
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} damaged/incomplete app safeguards')
