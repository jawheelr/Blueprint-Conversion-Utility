from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path
from .compiler import CompileOptions, FAMILY_ROOTS, compile_schema, write_outputs


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="apple-schema-compiler", description="Compile Apple's Device Management YAML into a deterministic BCU runtime catalog.")
    p.add_argument("source", type=Path, help="Root of Apple's device-management repository")
    p.add_argument("--output", "-o", type=Path, default=Path("dist"))
    p.add_argument("--family", action="append", choices=sorted(FAMILY_ROOTS), help="Compile only this family; repeat as needed")
    p.add_argument("--include-examples", action="store_true")
    p.add_argument("--pretty", action="store_true")
    p.add_argument("--strict", action="store_true", help="Return non-zero for compiler errors")
    p.add_argument("--list-families", action="store_true")
    return p


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    if args.list_families:
        print("\n".join(f"{k}: {v}" for k, v in sorted(FAMILY_ROOTS.items())))
        return 0
    if not args.source.exists():
        print(f"error: source does not exist: {args.source}", file=sys.stderr)
        return 2
    families = set(args.family or FAMILY_ROOTS.keys())
    catalog, index, diagnostics = compile_schema(args.source, CompileOptions(families=families, include_examples=args.include_examples, strict=args.strict, pretty=args.pretty))
    write_outputs(args.output, catalog, index, diagnostics, args.pretty)
    summary = {"objects": index["objectCount"], "keys": index["keyCount"], "wildcards": index["wildcardKeyCount"], "errors": sum(d.severity == "error" for d in diagnostics), "warnings": sum(d.severity == "warning" for d in diagnostics), "output": str(args.output)}
    print(json.dumps(summary, indent=2))
    return 1 if args.strict and summary["errors"] else 0

if __name__ == "__main__":
    raise SystemExit(main())
