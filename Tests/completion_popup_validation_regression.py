from pathlib import Path
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
content=Path('Sources/BlueprintCreator/ContentView.swift').read_text()
checks={
'completion helper':'validatedTakeoverCompletion(' in app,
'json response parsing':'JSONSerialization.jsonObject' in app and 'object["id"]' in app,
'deployment state parsing':'object["deploymentState"]' in app and 'state["state"]' in app,
'deployed validation':'finalDeploymentState == "DEPLOYED"' in app,
'partial deployment handling':'Partial completion: Blueprint created' in app,
'completion popup title':'Blueprint Created and Deployed' in app,
'validation details':'Validated: Blueprint created and Jamf Platform reports DEPLOYED.' in app,
'profile details':'Configuration Profile:' in app and 'Profile ID:' in app,
'blueprint details':'Blueprint ID:' in app,
'classic scope':'Classic Configuration Profile: Remains scoped' in app,
'dropped keys':'Dropped keys:' in app,
'popup binding':'.alert(item: $model.operationResult)' in content,
'completion published':'operationResult = completion' in app,
}
for n,v in checks.items(): assert v,n
print(f'PASS: {len(checks)} completion popup/validation checks')
print('PASS: source integration checks')
