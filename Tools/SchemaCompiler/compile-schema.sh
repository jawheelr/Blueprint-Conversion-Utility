#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${1:-}"
OUTPUT="${2:-$ROOT/dist}"
if [[ -z "$SOURCE" ]]; then
  echo "Usage: ./compile-schema.sh /path/to/device-management-release [output-directory]" >&2
  exit 2
fi
cd "$ROOT"
python3 -m schema_compiler "$SOURCE" --output "$OUTPUT" --pretty --strict
