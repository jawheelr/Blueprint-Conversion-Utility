from pathlib import Path
ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
pred=Path('Sources/BlueprintCreator/ActivationPredicate.swift').read_text()
kb=Path('Sources/BlueprintCreator/KnowledgeBaseView.swift').read_text()
checks={
'compact bar button':'Button("Edit Conditions")' in ui,
'editor sheet':'.sheet(isPresented: $showConditions)' in ui and 'ActivationConditionsEditor' in ui,
'visual text modes':'Text("Visual").tag(0)' in ui and 'Text("Text").tag(1)' in ui,
'match choices':'Match all' in ui and 'Match any' in ui,
'add condition':'Add Condition' in ui and 'rows.append(ActivationConditionRow())' in ui,
'remove condition':'Remove this condition' in ui and 'rows.removeAll' in ui,
'one row per condition':'ForEach($rows)' in ui,
'no single-expression Set button':'Button("Set")' not in ui,
'live preview':'ActivationPredicate.build(rows: rows, match: match)' in ui,
'unparseable stays text':'saved exactly as written' in ui and 'ActivationPredicate.parse(existing)' in ui,
'length guard':'maxLength' in ui and '.disabled(tooLong)' in ui,
'save to model':'model.blueprintActivationCondition =' in ui,
'serialize JSON':'model.applyBlueprintGUIToJSON()' in ui,
'clear conditions':'Clear Conditions' in ui,
'summary counts':'condition\\(count == 1' in ui and 'Custom predicate' in ui,
'writes API field':'steps[0]["activationPredicate"] = blueprintActivationCondition' in app,
'removes legacy key':'steps[0].removeValue(forKey: "activationCondition")' in app,
'reads API field with legacy fallback':'step["activationPredicate"] as? String ?? step["activationCondition"] as? String' in app,
'apple status keys':all(k in pred for k in ['device.operating-system.family','device.operating-system.version','device.model.family','device.identifier.serial-number','device.power.battery-health']),
'status form':'@status(' in pred and "IN {" in pred,
'joiners':'" AND "' in pred and '" OR "' in pred,
'jamf group property':'@property(jamf.device.groups)' in pred and 'NONE' in pred,
'negation form':'NOT (' in pred,
'quote escaping':"replacingOccurrences(of: \"'\", with: \"\\\\'\")" in pred,
'strict parse roundtrip':'build(rows: rows, match: match) == trimmed' in pred,
'knowledge base':'activationPredicate' in kb,
'old syntax gone':'notContains' not in ui and 'startsWith' not in ui,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} activation-condition integration checks')
for p in Path('Sources/BlueprintCreator').glob('*.swift'):
 s=p.read_text(); assert s.count('{')==s.count('}'),p
print('PASS: Swift brace balance')
