from pathlib import Path
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
assert 'deploymentEligibility.reasons.joined(separator: "\\n")' in app
assert 'Create Only remains available.\\n" + deploymentEligibility.reasons.joined(separator: "\\n")' in app
assert 'evaluateDeploymentSafeguards().reasons.joined(separator: "\\n")' in ui
assert 'joined(separator: "\n")' not in app
assert 'joined(separator: "\n")' not in ui
print('PASS: deployment strings use escaped newlines')
