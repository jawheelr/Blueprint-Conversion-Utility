from pathlib import Path
workflow=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
helptext=Path('Sources/BlueprintCreator/ProfileInspectorHelp.swift').read_text()
view=Path('Sources/BlueprintCreator/ProfileInspectorView.swift').read_text()
edit=Path('Sources/BlueprintCreator/ProfileSettingEditView.swift').read_text()
kb=Path('Sources/BlueprintCreator/KnowledgeBaseView.swift').read_text()
checks={
'placement':workflow.index('Button(showManualApproach ? "Hide Alternatives" : "Change Approach")') < workflow.index('Button("Profile Inspector")') < workflow.index('Button("View Analysis")'),
'post parse gating':'model.profileInspection == nil || model.profileInspectionLoading' in workflow,
'workflow tooltip':'Open the Profile Inspector for the evaluated profile' in workflow,
'action function':'static func recommendation(_ value: SettingRecommendation)' in helptext,
'all actions':all(x in helptext for x in ['case .keep','case .convert','case .edit','case .replace','case .remove','case .legacy','case .review','case .metadata']),
'badge tooltip':'help(ProfileInspectorHelp.recommendation(value))' in view,
'decision function':'static func decision(_ value: OverrideDecision)' in helptext,
'all decisions':all(x in helptext for x in ['case .apply','case .keepSource','case .reviewLater']),
'menu option tooltip':'help(ProfileInspectorHelp.decision(option))' in edit,
'decision tooltip':'help(ProfileInspectorHelp.decision(option))' in edit and 'InspectorHelpButton(title: option.rawValue' in edit,
'knowledge placement':'directly between Change Approach and View Analysis' in kb,
'knowledge tooltip':'Hover over every recommendation badge' in kb,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} placement and tooltip checks')
