from pathlib import Path
lines=Path('Sources/BlueprintCreator/AppModel.swift').read_text().splitlines()
regex_line=next(line for line in lines if 'combinedOutput.range(of:' in line)
split_line=next(line for line in lines if 'fragment.split(separator:' in line)
assert '#"' in regex_line and 'regularExpression' in regex_line and 'id' in regex_line
assert 'split(separator: "\\\"")' in split_line
source='\n'.join(lines)
assert 'let script = #"""\n' in source
assert '\n        """#' in source
assert 'separator: """)' not in source
print('PASS: raw regex, quote separator, and multiline shell literal syntax checks')
