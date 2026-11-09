from pathlib import Path
app = Path('Sources/BlueprintCreator/AppModel.swift').read_text()
ui = Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()

checks = {
    'profile change resets setup': '.onChange(of: model.selectedProfileID)' in ui and 'step = 0' in ui,
    'profile change resets advanced tab': '.onChange(of: model.selectedProfileID)' in ui and 'advancedTab = 0' in ui,
    'dry run is not verdict gated': 'if !dryRunEnabled && workflowMode == .takeover' in app,
    'real action remains verdict gated': 'takeoverVerdict != .supported' in app,
    'actionable prerequisite message': 'Run Dry-Run Preview and receive a current Takeover Supported verdict' in app,
    'dry run action remains present': 'Run Dry-Run Preview' in ui,
    'deployment actions remain present': 'Button("Create Only")' in ui and 'Button("Create and Deploy")' in ui,
}
for name, ok in checks.items():
    assert ok, name
    print('PASS:', name)

# Guard against the circular form returning.
assert 'if workflowMode == .takeover && importMode == .preserveInstalled && takeoverVerdict != .supported' not in app
print('PASS: no circular Dry Run prerequisite')

for path in Path('Sources/BlueprintCreator').glob('*.swift'):
    source = path.read_text()
    assert source.count('{') == source.count('}'), path
print('PASS: Swift source brace balance')
