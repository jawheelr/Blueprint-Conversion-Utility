from pathlib import Path
api = Path('Sources/BlueprintCreator/APIClients.swift').read_text()
model = Path('Sources/BlueprintCreator/AppModel.swift').read_text()
view = Path('Sources/BlueprintCreator/BlueprintGUIEditorView.swift').read_text()
checks = {
    '100 group page size': 'private let groupPageSize = 100' in model,
    'paged endpoint': 'func groups(page: Int = 0, pageSize: Int = 100)' in api,
    'no eager loop': 'while true' not in api[api.index('func groups(page:'):api.index('func createBlueprint')],
    'next page state': 'private var nextGroupPage = 0' in model,
    'has more state': '@Published private(set) var hasMoreGroups = false' in model,
    'scroll threshold': 'groups.count - 10' in model,
    'duplicate request guard': '!groupsLoadingMore' in model,
    'append not replace': 'allGroups.append(contentsOf: additions)' in model,
    'deduplicate IDs': 'Set(allGroups.map(\\.id))' in model,
    'end-row trigger': 'loadMoreGroupsIfNeeded(currentGroup: group)' in view,
    'loading indicator': 'Loading more groups...' in view,
}
for name, ok in checks.items():
    assert ok, name
print(f'PASS: {len(checks)} lazy group pagination checks')
