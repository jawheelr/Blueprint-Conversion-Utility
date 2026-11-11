from pathlib import Path
engine=Path('Sources/BlueprintCreator/SettingEvaluation.swift').read_text()
view=Path('Sources/BlueprintCreator/ProfileInspectorView.swift').read_text()
content=Path('Sources/BlueprintCreator/ContentView.swift').read_text()
menu=Path('Sources/BlueprintCreator/BlueprintCreatorApp.swift').read_text()
checks={
'recommendations':all(x in engine for x in ['case keep','case convert','case edit','case replace','case remove','case legacy','case review','case metadata']),
'timing':'RecommendationTiming' in engine and 'Before Blueprint creation' in engine,
'confidence':'RecommendationConfidence' in engine,
'lifecycle rules':'node.schema.lifecycle == .removed' in engine and 'node.schema.lifecycle == .deprecated' in engine,
'unknown rule':'node.schema.kind == .unknown' in engine,
'wildcard rule':'node.schema.kind == .wildcard' in engine,
'wifi rule':'encryptiontype' in engine and 'intentionally open' in engine,
'payload rollup':'static func evaluate(_ payload:' in engine,
'default expanded':'initialize()' in view and 'expandConfigured()' in view,
'expand controls':all(x in view for x in ['Expand All','Collapse All','Expand Configured']),
'search expansion':'expandSearchMatches()' in view,
'evaluation detail':all(x in view for x in ['Recommended action','When to edit','Migration behavior','Confidence','Evidence']),
'badges':'struct RecommendationBadge' in view,
'action filter':'Action Needed' in view,
'read only':'Source profile is read-only' in view,
'no footer browser':'Button("Apple Schema Browser")' not in view,
'no main header browser':'Button("Apple Schema")' not in content,
'help browser':'Button("Apple Schema Browser")' in menu,
'context schema':'Open Schema Definition' in view,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} inspector recommendation/expansion checks')
