from pathlib import Path
src=Path('Sources/BlueprintCreator')
app=(src/'AppModel.swift').read_text()
models=(src/'Models.swift').read_text()
store=(src/'ConnectionStore.swift').read_text()
kc=(src/'KeychainStore.swift').read_text()
cv=(src/'ContentView.swift').read_text()
cn=(src/'ConnectionsView.swift').read_text()
kb=(src/'KnowledgeBaseView.swift').read_text()
cli=Path('Sources/BCUCLI/main.swift').read_text()
checks={
'connection model':'struct PlatformConnection: Codable, Identifiable' in models and 'var environmentID' in models and 'func applied() -> AppSettings' in models,
'no secret field on model':'clientSecret' not in models.split('struct PlatformConnection')[1].split('enum PlatformCredentialHealth')[0],
'store key and migration':'BlueprintCreator.Connections' in store and 'func loadOrMigrate' in store,
'migration copies secret per id':'saveSecret(secret, connection.id)' in store,
'legacy settings mirror':'func mirrorActive' in store and 'BlueprintCreator.Settings' in store,
'cli still reads legacy keys':'BlueprintCreator.Settings' in cli and 'platform-api-client-secret' in cli,
'per-connection keychain accounts':'func saveSecret(_ platform: String, for id: UUID)' in kc and 'uuidString.lowercased()' in kc and 'func deleteSecret(for id: UUID)' in kc,
'model state':'private(set) var connections' in app and 'private(set) var activeConnectionID' in app,
'init loads active connection':'ConnectionStore.loadOrMigrate()' in app and 'KeychainStore.readSecret(for: active.id)' in app,
'save persists connection':'try persistActiveConnection()' in app,
'switch guards busy':'guard id != activeConnectionID, !busy' in app,
'switch resets workspace':'resetWorkspaceForConnectionChange()' in app and 'profileLoadGeneration += 1' in app.split('func resetWorkspaceForConnectionChange')[1][:600],
'switch revalidates':'await launch()' in app.split('func selectConnection')[1][:900],
'add and delete':'func addConnection()' in app and 'func deleteActiveConnection()' in app and 'KeychainStore.deleteSecret(for: id)' in app,
'delete keeps one':'connections.count > 1' in app,
'header menu only for several':'model.connections.count > 1' in cv and 'Switch environment' in cv and 'Manage Connections...' in cv,
'header status states':'API Ready' in cv and 'Check connection' in cv and 'Checking...' in cv and '.yellow' in cv and '.red' in cv and '.green' in cv,
'status left of menu':cv.index('statusLabel\n                Menu') < cv.index('Switch environment'),
'menu disabled while busy':'.disabled(model.busy)' in cv,
'active name in header':'model.activeConnectionName' in cv,
'connections picker row':'connectionPicker' in cn and 'model.addConnection()' in cn and 'confirmationDialog' in cn,
'remove confirms keychain delete':'saved client secret is deleted from the Keychain' in cn,
'knowledge base':'save several Platform connections' in kb,
}
for name,ok in checks.items(): assert ok,name
print(f'PASS: {len(checks)} connection checks')
for p in src.glob('*.swift'):
 s=p.read_text(); assert s.count('{')==s.count('}'),p
print('PASS: Swift brace balance')
