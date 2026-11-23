from pathlib import Path

issue=Path('Sources/BlueprintCreator/PlatformIssue.swift').read_text()
api=Path('Sources/BlueprintCreator/APIClients.swift').read_text()
app=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
models=Path('Sources/BlueprintCreator/Models.swift').read_text()
conn=Path('Sources/BlueprintCreator/ConnectionsView.swift').read_text()
content=Path('Sources/BlueprintCreator/ContentView.swift').read_text()
kb=Path('Sources/BlueprintCreator/KnowledgeBaseView.swift').read_text()
checks={
'capabilities':all(c in issue for c in ['groupsRead','blueprintsRead','blueprintsCreate','blueprintsDeploy','profilesUpdate']),
'grant text':'Inventory > Device Groups: Read' in issue and 'Deployment > Blueprints: Deploy' in issue,
'classifier':'static func classify(status: Int' in issue and 'case 403:' in issue and 'case 429:' in issue,
'token message':'Jamf did not issue an access token' in issue,
'failure type':'case platform(PlatformIssue)' in models,
'validate has context':'path: String = ""' in api and 'isTokenRequest' in api,
'both token calls classified':api.count('isTokenRequest: true')==2,
'read-only probes':'func probeReadAccess()' in api and 'func probeProfileAccess()' in api,
'probes use GET only':'method: "GET"' in api,
'shared check':'runAccessChecks()' in app and app.count('await runAccessChecks()')==2,
'report reset on switch':'permissionReport = []' in app,
'limited access':'limitedAccessProblem' in app and 'Limited access' in content,
'header help':'statusHelp' in content,
'permissions ui':'permissionsSection' in conn and 'Copy Details' in conn,
'write perms when used':'checkedWhenUsed' in issue and 'Checked when used' in app,
'unscope hint':'issue.message' in api and 'method: "PUT"' in api,
'kb':'Permission checks' in kb,
'no secret in report':'platformSecret' not in issue and 'clientSecret' not in issue,
}
bad=[k for k,v in checks.items() if not v]
assert not bad, bad
print('PASS: platform issue regression')
