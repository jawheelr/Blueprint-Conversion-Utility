from pathlib import Path
view=Path('Sources/BlueprintCreator/ProfileInspectorView.swift').read_text()
edit=Path('Sources/BlueprintCreator/ProfileSettingEditView.swift').read_text()
overrides=Path('Sources/BlueprintCreator/ProfileEditOverrides.swift').read_text()
model=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
schema=Path('Sources/BlueprintCreator/AppleSchemaBrowserView.swift').read_text()
kb=Path('Sources/BlueprintCreator/KnowledgeBaseView.swift').read_text()
checks={
'whole row profile':'.contentShape(Rectangle())' in view and '.frame(maxWidth: .infinity, alignment: .leading)' in view,
'easy button':'Resolve Before Continuing' in view,
'edit sheet':'ProfileSettingEditView' in view and '.sheet(item: $editTarget)' in view,
'decisions':all(x in overrides for x in ['Apply to Destination','Keep Source Value','Review Later']),
'source read only':'is not modified' in edit,
'override state':'profileSettingOverrides' in model,
'unresolved analysis':'unresolvedInspectorRecommendations' in model and 'need a decision' in view,
'clear per profile':'profileSettingOverrides = [:]' in model,
'schema expand controls':all(x in schema for x in ['Expand All','Collapse All','Expand Configured']),
'schema whole row':'.contentShape(Rectangle())' in schema,
'schema centralized state':'expandedSchemaPaths' in schema,
'search expansion':'expandSchemaSearchMatches' in schema,
'wrapped details':'.fixedSize(horizontal: false, vertical: true)' in schema,
'knowledge':'Resolve Before Continuing' in kb and 'Apple Schema Browser' in kb,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} easy-edit and schema-browser checks')
