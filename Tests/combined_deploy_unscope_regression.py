from pathlib import Path
models=Path('Sources/BlueprintCreator/TakeoverModels.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
ui=Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
content=Path('Sources/BlueprintCreator/ContentView.swift').read_text()
svc=Path('Sources/BlueprintCreator/TakeoverImportService.swift').read_text()
checks={
'third intent':'case createDeployAndUnscope' in models,
'deployment helper':'var requestsDeployment: Bool' in models,
'unscope helper':'var requestsUnscope: Bool' in models,
'standalone deploy':'performGuidedFinalAction(deploymentIntent: .createAndDeploy)' in ui,
'combined action':'Button("Create, Deploy, and Unscope")' in ui,
'confirmation sheet':'showDeployAndUnscopeConfirmation' in content,
'ack required':'deployAndUnscopeAcknowledged' in app and content,
'deploy flag all deploy intents':'deploymentIntent.requestsDeployment' in svc,
'unscope only combined':'if deploymentIntent.requestsUnscope' in app,
'deployed prerequisite':'guard lastTakeoverDeploymentValidated' in app,
'profile remains scoped if not validated':'Unscope Not Performed' in app,
'partial unscope failure':'Blueprint Deployed - Profile Unscope Failed' in app,
'real result not overwritten':'Real operations set their own completed/partial/failed result' in app,
}
for n,v in checks.items(): assert v,n
print(f'PASS: {len(checks)} combined deploy/unscope checks')
