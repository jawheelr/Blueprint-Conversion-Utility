from pathlib import Path
models=Path('Sources/BlueprintCreator/TakeoverModels.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
checks={
'recommendation enum':'enum RecommendedProfileApproach' in models,
'all recommendation states':all(x in models for x in ['case analyzing','case takeover','case convert','case createForReview','case unavailable','case evaluationIncomplete']),
'profile selection resets analysis':'recommendedApproach = .analyzing' in app,
'automatic recommendation helper':'applyAutomaticRecommendation(for verdict:' in app,
'takeover selects preserve installed':'importMode = .preserveInstalled' in app,
'unsupported selects convert':'recommendation = conversionReady ? .convert' in app and 'importMode = .convert' in app,
'incomplete classification':'processed the profile but did not return a recognizable final takeover verdict' in app,
'concrete failure distinction':'let concreteFailure = messages.contains' in app,
'recommendation card':'Label("Recommended Approach"' in ui,
'old technical card removed':'Label("Conversion Options"' not in ui,
'manual alternatives hidden':'Change Approach' in ui and 'showManualApproach' in ui,
'analysis access':'Button("View Analysis")' in ui,
'scope intervention':'Choose Another Group' in ui,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} automatic recommendation checks')
print('PASS: source integration checks')
