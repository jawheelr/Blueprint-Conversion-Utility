from pathlib import Path
content=Path('Sources/BlueprintCreator/ContentView.swift').read_text()
workflow=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
kb=Path('Sources/BlueprintCreator/KnowledgeBaseView.swift').read_text()
view=Path('Sources/BlueprintCreator/ProfileInspectorView.swift').read_text()
edit=Path('Sources/BlueprintCreator/ProfileSettingEditView.swift').read_text()
helpbutton=Path('Sources/BlueprintCreator/InspectorHelpButton.swift').read_text()
checks={
'global header removed':'Button("Profile Inspector")' not in content,
'evaluated placement':workflow.index('Button("Profile Inspector")') < workflow.index('Button("View Analysis")'),
'evaluation gating':'profileInspection == nil || model.profileInspectionLoading' in workflow,
'dedicated KB topic':'case profileInspector = "Profile Inspector"' in kb,
'dedicated KB article':'case .profileInspector:' in kb and 'Resolve Before Continuing' in kb,
'dedicated KB icon':'case .profileInspector: return "doc.text.magnifyingglass"' in kb,
'visible help control':'struct InspectorHelpButton' in helpbutton and '.popover(isPresented:' in helpbutton,
'whole row tooltip':'help(ProfileInspectorHelp.recommendation(evaluation.recommendation))' in view,
'recommendation info buttons':view.count('InspectorHelpButton(title: evaluation.recommendation.rawValue') >= 2,
'decision choices visible':'ForEach(OverrideDecision.allCases)' in edit and 'largecircle.fill.circle' in edit,
'decision hover':'.help(ProfileInspectorHelp.decision(option))' in edit,
'decision visible help':'InspectorHelpButton(title: option.rawValue' in edit,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} final UI checks')
