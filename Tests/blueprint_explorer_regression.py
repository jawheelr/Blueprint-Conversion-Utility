from pathlib import Path

api=Path('Sources/BlueprintCreator/APIClients.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
ext=Path('Sources/BlueprintCreator/AppModel+Explorer.swift').read_text()
view=Path('Sources/BlueprintCreator/BlueprintExplorerView.swift').read_text()
comp=Path('Sources/BlueprintCreator/ComponentSettingsEditor.swift').read_text()
content=Path('Sources/BlueprintCreator/ContentView.swift').read_text()
root=Path('Sources/BlueprintCreator/BlueprintCreatorApp.swift').read_text()
models=Path('Sources/BlueprintCreator/BlueprintExplorerModels.swift').read_text()
checks={
'list client':'func listBlueprints()' in api and 'if records.isEmpty { break }' in api,
'detail client':'func blueprintJSON(id: String)' in api,
'merge patch':'application/merge-patch+json' in api and 'method: "PATCH"' in api,
'undeploy client':'/undeploy' in api,
'ids validated':api.count('Validators.requireSafeIdentifier')>=5,
'sheet':'$model.showExplorer' in content and 'BlueprintExplorerView()' in content,
'header button':'Button("Blueprints")' in content,
'menu':'Blueprints Explorer' in root,
'connection reset':'resetExplorer()' in app and 'showExplorer = false' in ext,
'stale guard':'explorerGeneration' in ext and 'guard generation == explorerGeneration' in ext,
'confirmation':'explorerPendingAction' in ext and 'confirmationDialog' in view,
'conflict check':'changed in Jamf after you opened it' in ext,
'validation':'Scope needs at least one device group' in ext and 'The name cannot be empty' in ext,
'full arrays sent':'body["steps"] = draft["steps"]' in ext and 'body["scope"] = draft["scope"]' in ext,
'dirty discard':'Discard unsaved changes' in view,
'raw json fallback':'Raw JSON' in comp and 'Apply JSON' in comp,
'schema forms':'ExplorerSchemaResolver' in comp and 'enumChoices' in comp,
'number types kept':'static func number(from' in models and 'Int64(trimmed)' in models,
'no secrets logged':'platformSecret' not in ext and 'clientSecret' not in ext,
}
bad=[k for k,v in checks.items() if not v]
assert not bad, bad
print('PASS: blueprint explorer regression')
