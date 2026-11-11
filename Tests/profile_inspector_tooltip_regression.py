from pathlib import Path
helptext=Path('Sources/BlueprintCreator/ProfileInspectorHelp.swift').read_text()
view=Path('Sources/BlueprintCreator/ProfileInspectorView.swift').read_text()
edit=Path('Sources/BlueprintCreator/ProfileSettingEditView.swift').read_text()
kb=Path('Sources/BlueprintCreator/KnowledgeBaseView.swift').read_text()
checks={
'help source':helptext.count('static let') >= 12,
'native gui':"Native Blueprint/DDM components may be editable" in helptext,
'api caveat':"API acceptance alone does not guarantee" in helptext,
'wrapper':"configuration-profile wrapper" in helptext,
'apply meaning':"Apply to Destination records" in helptext,
'keep meaning':"Keep Source Value preserves" in helptext,
'review meaning':"Review Later deliberately" in helptext,
'inspector tooltips':view.count('.help(') >= 8,
'editor tooltips':edit.count('.help(') >= 4,
'knowledge categories':'Understanding destination decisions' in kb and 'Preserve as Legacy' in kb,
'knowledge editability':'Native Blueprint components and profile wrappers' in kb,
'knowledge verification':'verify on Review' in kb,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} documentation and tooltip checks')
