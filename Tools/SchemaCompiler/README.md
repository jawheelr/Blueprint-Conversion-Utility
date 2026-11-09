# Apple Device Management Schema Compiler

This is the first implementation phase for the Blueprint Conversion Utility schema system. It compiles Apple's Device Management YAML repository into a normalized, deterministic runtime catalog and search index suitable for BCU's future Profile Inspector and migration engine.

## Outputs

- `apple-device-management-catalog.json`: normalized schema objects and recursive keys.
- `apple-device-management-index.json`: object, identifier, key-path, lifecycle, and wildcard indexes.
- `compile-report.json`: object/key counts and compiler diagnostics.

## Preserved metadata

The compiler preserves payload/declaration identifiers, titles, descriptions, recursive subkeys, `ANY` wildcard nodes, types, presence, defaults, formats, allowed values, ranges, repetition, combine behavior, supported OS metadata, lifecycle versions, enrollment/scoping metadata, references, extensions, and original source paths.

## Usage

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .

./compile-schema.sh /path/to/device-management-release ./dist
```

Or:

```bash
python3 -m schema_compiler /path/to/device-management-release \
  --output ./dist \
  --pretty \
  --strict
```

Compile selected families:

```bash
python3 -m schema_compiler /path/to/device-management-release \
  --family mdm-profile \
  --family declarative-configuration \
  --family declarative-asset \
  --family declarative-activation \
  --output ./dist
```

## Runtime lookup strategy

BCU should resolve metadata by schema family, object identifier, and full nested key path. It must not use a global key-to-label dictionary. `ANY` is retained as a wildcard node for dynamic dictionaries such as Managed Preferences and vendor settings.

## Reproducibility

Objects, mappings, indexes, and diagnostics are sorted before serialization. `generatedAt` changes between runs; the schema object ordering and content remain deterministic for a given Apple source tree and compiler version.

## Tests

```bash
python3 -m unittest discover -s tests -v
```

## Attribution

Apple's source `LICENSE.txt` is copied into `THIRD-PARTY-NOTICES/Apple-Device-Management-LICENSE.txt`. The compiler itself is separate from Apple's source and does not require bundling the complete upstream repository into BCU.
