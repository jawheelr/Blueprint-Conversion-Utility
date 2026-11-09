from pathlib import Path
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text(); ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text(); kb=Path('Sources/BlueprintCreator/KnowledgeBaseView.swift').read_text()
checks={
'version':'3.5.0' in Path('Info.plist').read_text() and 'APP_VERSION:-3.5.0' in Path('build.sh').read_text(),
'activity clear':'takeoverRawOutput = ""' in app[app.index('func select('):app.index('do {',app.index('func select('))],
'late guard':'selectedProfileID == evaluatedProfileID' in app and 'profileLoadGeneration == evaluatedGeneration' in app,
'scheduled guard':'scheduledGeneration = profileLoadGeneration' in app,
'selected approach':'@Published var selectedApproach' in app and 'if !hasUserSelectedApproach' in app,
'target below scope':ui.index('Picker("Scope"') < ui.index('Picker("Target Group"'),
'admin guide':kb.count('heading("Admin Start Guide"') == 1 and 'case .adminStart: return "checklist"' in kb,
'build script':Path('build.sh').exists(),
}
for n,v in checks.items(): assert v,n
print(f'PASS: {len(checks)} BCU 3.5.0 release-block checks')
