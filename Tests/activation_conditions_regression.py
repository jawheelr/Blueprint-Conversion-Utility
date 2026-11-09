from pathlib import Path
ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
checks={
'compact bar button':'Button("Edit Conditions")' in ui,
'editor sheet':'.sheet(isPresented: $showConditions)' in ui and 'ActivationConditionsEditor' in ui,
'visual text modes':'Text("Visual").tag(0)' in ui and 'Text("Text").tag(1)' in ui,
'match choices':'Match all' in ui and 'Match any' in ui,
'attributes':'Operating system version' in ui and 'FileVault enabled' in ui and 'Serial number' in ui,
'operators':'does not contain' in ui and 'does not start with' in ui and 'does not match' in ui,
'type aware boolean':'Text("Yes").tag("true")' in ui and 'Text("No").tag("false")' in ui,
'type aware architecture':'Apple silicon' in ui and 'x86_64' in ui,
'save to model':'model.blueprintActivationCondition =' in ui,
'serialize JSON':'model.applyBlueprintGUIToJSON()' in ui,
'clear conditions':'Clear Conditions' in ui,
'existing model serializer':'steps[0]["activationCondition"] = blueprintActivationCondition' in app,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} activation-condition integration checks')
for p in Path('Sources/BlueprintCreator').glob('*.swift'):
 s=p.read_text(); assert s.count('{')==s.count('}'),p
print('PASS: Swift brace balance')
