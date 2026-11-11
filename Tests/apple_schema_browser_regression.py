from pathlib import Path
import json

models=Path('Sources/BlueprintCreator/AppleSchemaModels.swift').read_text()
service=Path('Sources/BlueprintCreator/AppleSchemaService.swift').read_text()
view=Path('Sources/BlueprintCreator/AppleSchemaBrowserView.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
root=Path('Sources/BlueprintCreator/BlueprintCreatorApp.swift').read_text()
content=Path('Sources/BlueprintCreator/ContentView.swift').read_text()
build=Path('build.sh').read_text()
catalog=json.loads(Path('Resources/AppleSchema/apple-device-management-catalog.json').read_text())
index=json.loads(Path('Resources/AppleSchema/apple-device-management-index.json').read_text())
checks={
'catalog objects':len(catalog['objects'])==342,
'catalog keys':index['keyCount']==4230,
'wildcards':index['wildcardKeyCount']==54,
'model families':'enum AppleSchemaFamily' in models and 'Configuration Profiles' in models,
'full path':'pathString' in models,
'wildcard support':'wildcard' in models,
'lifecycle':'enum AppleSchemaLifecycle' in models,
'bundle loader':'Bundle.main.url' in service and 'subdirectory: "AppleSchema"' in service,
'search':'Search titles, identifiers, raw keys, descriptions, or paths' in view,
'disclosure arrows':'DisclosureGroup(isExpanded:' in view,
'family filter':'Picker("Family"' in view,
'lifecycle filter':'Picker("Lifecycle"' in view,
'copy actions':'Copy Raw Key' in view and 'Copy Full Path' in view,
'menu entry':'Apple Schema Browser' in root,
'context entry':'Open Schema Definition' in Path('Sources/BlueprintCreator/ProfileInspectorView.swift').read_text(),
'sheet':'.sheet(isPresented: $model.showAppleSchema)' in content,
'app state':'@Published var showAppleSchema = false' in app,
'build script':Path('build.sh').exists(),
'resource validation':'Apple schema catalog is missing' in build,
'resource copy':'cp Resources/AppleSchema/*.json' in build,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} Apple Schema Browser integration checks')
