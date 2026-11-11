from pathlib import Path
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
checks={
'unscoped discovery no early return':'Compatibility discovery will continue' in app,
'dry run permits missing target':'if !dryRun && importScopeMode == .overrideSelected' in app,
'takeover recommendation retained':'Takeover is supported. Choose a compatible target group before deployment.' in app,
'group picker visible':'Picker("Target Group"' in ui,
'group loading':'Loading compatible groups...' in ui,
'group error retry':'Retry Groups' in ui and 'reloadCompatibleGroups()' in app,
'empty groups':'No compatible' in ui and 'groups were returned.' in ui,
'family source':'applyGroupFilter()' in app,
'balanced parser':'func balancedJSONObjects' in app,
'escaped quote handling':'var escaped = false' in app,
'balanced state':'var depth = 0' in app,
'mixed output parser':'for object in balancedJSONObjects(in: combined)' in app,
}
for n,v in checks.items(): assert v,n
print(f'PASS: {len(checks)} preliminary scope/parser checks')
