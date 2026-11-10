from pathlib import Path
s=Path('build.sh').read_text()
checks={
'incomplete feature gate':'JAMF_SOURCE_COMPLETE=1' in s,
'required package checks':'internal/$package' in s,
'project binaries':'Resources/bin/$name' in s,
'managed binaries':'$HOME/.local/bin/$name' in s,
'path binaries':'command -v "$name"' in s,
'compile only complete':'[[ "$JAMF_SOURCE_COMPLETE" -eq 1' in s,
'official jamf-cli release':'Jamf-Concepts/jamf-cli/releases/download' in s,
'jamf-cli checksum verified':'shasum -a 256' in s and 'checksum mismatch' in s,
'takeover capability required':'--takeover-only' in s,
'optional helper copy':'[[ -z "$JAMF_CLI_SOURCE" ]] || cp' in s,
'dynamic signing':'find "$STAGE_APP/Contents/Resources/bin" -type f' in s,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} Go helper resolution checks')
