from pathlib import Path
s=Path('Sources/BlueprintCreator/AppModel.swift').read_text()
assert 'if depth == 0, let objectStart = start {' in s
assert 'String(characters[objectStart...index])' in s
assert 'if depth == 0, let start {' not in s
assert 'start = nil' in s
print('PASS: balanced JSON parser no longer shadows mutable start')
