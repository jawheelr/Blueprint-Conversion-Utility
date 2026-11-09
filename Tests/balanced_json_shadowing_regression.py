from pathlib import Path
s = Path('Sources/BlueprintCreator/AppModel.swift').read_text()
assert 'if depth == 0, let objectStart = start {' in s
assert 'String(characters[objectStart...index])' in s
assert 'start = nil' in s
assert 'if depth == 0, let start {' not in s
print('PASS: optional start index is not shadowed by immutable binding')
