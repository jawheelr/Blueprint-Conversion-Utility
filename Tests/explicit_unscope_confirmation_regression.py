from pathlib import Path
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
content=Path('Sources/BlueprintCreator/ContentView.swift').read_text()
ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
checks={
'post deploy state':'lastTakeoverDeploymentValidated' in app and 'lastTakeoverBlueprintID' in app,
'confirmation state':'showTakeoverUnscopeConfirmation' in app and 'takeoverUnscopeAcknowledged' in app,
'validated deployment required':'guard lastTakeoverDeploymentValidated' in app,
'ack required':'guard takeoverUnscopeAcknowledged' in app,
'actual unscope separate':'unscopeProfile(id: profile.id, mobile: mobile)' in app,
'profile change revokes':'lastTakeoverDeploymentValidated = false' in app,
'review action':'Button("Review Classic Profile")' in ui,
'confirmation sheet':'.sheet(isPresented: $model.showTakeoverUnscopeConfirmation)' in content,
'warning language':'separate lifecycle action' in content,
'checkbox':'toggleStyle(.checkbox)' in content,
'destructive action':'Button("Unscope Classic Configuration Profile", role: .destructive)' in content,
'completion result':'Classic Configuration Profile Unscoped' in app,
}
for n,v in checks.items(): assert v,n
print(f'PASS: {len(checks)} explicit unscope confirmation checks')
