from pathlib import Path
models=Path('Sources/BlueprintCreator/ProfileInspectorModels.swift').read_text()
parser=Path('Sources/BlueprintCreator/ProfileParser.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
checks={
    'typed values':'enum ProfileValue' in models and all(x in models for x in ['case dictionary','case array','case string','case integer','case real','case boolean','case date','case data']),
    'document model':'struct ProfileInspectorDocument' in models,
    'payload model':'struct ProfileInspectorPayload' in models,
    'recursive node':'struct ProfileInspectorNode' in models and 'children: [ProfileInspectorNode]' in models,
    'schema match kinds':all(x in models for x in ['case exact','case wildcard','case unknown']),
    'mobileconfig input':'func parseMobileconfig' in parser and 'PropertyListSerialization.propertyList' in parser,
    'payload type lookup':'payload["PayloadType"]' in parser,
    'mdm profile preference':'$0.family == "mdm-profile"' in parser,
    'exact before wildcard':'let exact =' in parser and 'let wildcard = exact == nil' in parser,
    'nested context':'schemaCandidates: schemaKey?.children ?? []' in parser,
    'unknown preservation':'No exact or wildcard Apple schema key matched' in parser,
    'profile reset':'profileInspection = nil' in app and 'profileInspectionLoading = true' in app,
    'generation guard':'generation == profileLoadGeneration' in app and 'selectedProfileID == profile.id' in app,
    'selection integration':'buildProfileInspection(for: detail, generation: generation)' in app,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} profile parser integration checks')
