from pathlib import Path
api=Path('Sources/BlueprintCreator/APIClients.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
checks={
'api readback':'func blueprintDeploymentState(id: String) async throws -> String?' in api,
'get endpoint':'path: "blueprints/v1/blueprints/\\(id)"' in api and 'method: "GET"' in api,
'nested state':'object["deploymentState"] as? [String: Any]' in api,
'bounded backoff':'let delays: [UInt64] = [2, 3, 5, 8, 12, 15]' in app,
'async sleep':'try await Task.sleep' in app,
'poll api':'blueprintDeploymentState(id: blueprintID)' in app,
'deployed success':'finalDeploymentState == "DEPLOYED"' in app,
'partial completion':'Blueprint Created - Deployment Verification Incomplete' in app,
'no immediate not deployed throw':'deployment validation returned' not in app,
'unscope gated':'lastTakeoverDeploymentValidated = completion.title == "Blueprint Created and Deployed"' in app,
'profile switch guard':'selectedProfileID == profile.id' in app,
}
for n,v in checks.items(): assert v,n
print(f'PASS: {len(checks)} deployment polling/read-back checks')
