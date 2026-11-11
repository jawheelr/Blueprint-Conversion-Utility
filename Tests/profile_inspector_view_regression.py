from pathlib import Path
view=Path('Sources/BlueprintCreator/ProfileInspectorView.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
content=Path('Sources/BlueprintCreator/ContentView.swift').read_text()
menu=Path('Sources/BlueprintCreator/BlueprintCreatorApp.swift').read_text()
build=Path('build.sh').read_text()
checks={
'profile inspector view':'struct ProfileInspectorView' in view,
'three pane layout':'HSplitView' in view and 'payloadList.frame' in view and 'details.frame' in view,
'disclosure arrows':'DisclosureGroup(isExpanded:' in view,
'search':'Search payloads, friendly names, raw keys, paths, descriptions, or values' in view,
'finding filters':all(x in view for x in ['Unknown','Wildcard Matches','Deprecated','Removed']),
'value details':'Source value' in view and 'Value type' in view,
'schema details':'Apple Schema Path' in view and 'Apple Schema Source' in view,
'copy actions':'Copy Key' in view and 'Copy Path' in view and 'Copy Value' in view,
'app state':'@Published var showProfileInspector = false' in app,
'sheet':'.sheet(isPresented: $model.showProfileInspector)' in content,
'header button removed':'Button("Profile Inspector")' not in content,
'menu button':'Button("Profile Inspector")' in menu,
'bin path discovery':'--show-bin-path' in build,
'standalone app':'Standalone app:' in build,
'standalone zip':'Standalone ZIP:' in build,
'pkg':'Installer PKG:' in build,
'dmg':'Disk image DMG:' in build,
'app verification':'Published standalone app is incomplete' in build and 'Main app executable is absent from the staged bundle' in build,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} Profile Inspector/build-output checks')
