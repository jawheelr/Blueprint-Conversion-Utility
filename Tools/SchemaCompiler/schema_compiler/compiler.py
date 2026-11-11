from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import yaml

FAMILY_ROOTS = {
    "mdm-profile": "mdm/profiles",
    "mdm-command": "mdm/commands",
    "mdm-checkin": "mdm/checkin",
    "mdm-error": "mdm/errors",
    "declarative-configuration": "declarative/declarations/configurations",
    "declarative-asset": "declarative/declarations/assets",
    "declarative-activation": "declarative/declarations/activations",
    "declarative-management": "declarative/declarations/management",
    "declarative-status": "declarative/status",
    "declarative-protocol": "declarative/protocol",
    "other": "other",
}

IDENTIFIER_FIELDS = ("payloadtype", "declarationtype", "requesttype", "checkintype", "statustype", "protocoltype", "type")


@dataclass
class Diagnostic:
    severity: str
    code: str
    file: str
    message: str

    def as_dict(self) -> dict[str, str]:
        return {"severity": self.severity, "code": self.code, "file": self.file, "message": self.message}


@dataclass
class CompileOptions:
    families: set[str] = field(default_factory=lambda: set(FAMILY_ROOTS))
    include_examples: bool = False
    strict: bool = False
    pretty: bool = False


def clean_text(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    return re.sub(r"[ \t]+\n", "\n", value).strip()


def normalize_scalar(value: Any) -> Any:
    if isinstance(value, str):
        return clean_text(value)
    return value


def normalize_supported_os(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {}
    result: dict[str, Any] = {}
    for platform, metadata in sorted(value.items(), key=lambda x: str(x[0]).lower()):
        if metadata is None:
            metadata = {}
        result[str(platform)] = normalize_mapping(metadata) if isinstance(metadata, dict) else normalize_scalar(metadata)
    return result


def normalize_mapping(value: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key in sorted(value, key=lambda x: str(x).lower()):
        item = value[key]
        if isinstance(item, dict):
            result[str(key)] = normalize_mapping(item)
        elif isinstance(item, list):
            result[str(key)] = [normalize_mapping(v) if isinstance(v, dict) else normalize_scalar(v) for v in item]
        else:
            result[str(key)] = normalize_scalar(item)
    return result


def normalize_key(raw: dict[str, Any], parent_path: tuple[str, ...], diagnostics: list[Diagnostic], source: str, ancestors: frozenset[int] = frozenset()) -> dict[str, Any]:
    raw_id = id(raw)
    key = str(raw.get("key", ""))
    if raw_id in ancestors:
        diagnostics.append(Diagnostic("warning", "recursive-alias", source, f"Recursive YAML alias encountered beneath {'.'.join(parent_path) or '<root>'}; emitted as a schema reference."))
        return {"key": key or "<recursive>", "path": list(parent_path + (key or "<recursive>",)), "pathString": ".".join(parent_path + (key or "<recursive>",)), "wildcard": key == "ANY", "recursiveReference": True, "children": []}
    if not key:
        diagnostics.append(Diagnostic("error", "missing-key-name", source, f"A payload key at {'.'.join(parent_path) or '<root>'} has no key."))
        key = "<missing>"
    path = parent_path + (key,)
    known = {
        "key", "title", "content", "description", "type", "presence", "default", "range", "rangelist", "values",
        "subkeys", "supportedOS", "format", "repetition", "combinetype", "requiredif", "requires", "excludes",
        "facets", "additionalProperties", "assettypes", "references", "value", "allowed", "minimum", "maximum"
    }
    node: dict[str, Any] = {
        "key": key,
        "path": list(path),
        "pathString": ".".join(path),
        "wildcard": key == "ANY",
    }
    title = raw.get("title")
    if title is not None:
        node["title"] = clean_text(title)
    description = raw.get("content", raw.get("description"))
    if description is not None:
        node["description"] = clean_text(description)
    for field_name in ("type", "presence", "default", "format", "combinetype", "range", "rangelist", "values", "repetition", "requiredif", "requires", "excludes", "facets", "additionalProperties", "assettypes", "references", "value", "allowed", "minimum", "maximum"):
        if field_name in raw:
            value = raw[field_name]
            node[field_name] = normalize_mapping(value) if isinstance(value, dict) else [normalize_mapping(v) if isinstance(v, dict) else normalize_scalar(v) for v in value] if isinstance(value, list) else normalize_scalar(value)
    if "supportedOS" in raw:
        node["supportedOS"] = normalize_supported_os(raw["supportedOS"])
    children = raw.get("subkeys") or []
    if not isinstance(children, list):
        diagnostics.append(Diagnostic("error", "invalid-subkeys", source, f"{node['pathString']} has non-array subkeys."))
        children = []
    node["children"] = [normalize_key(c, path, diagnostics, source, ancestors | {raw_id}) for c in children if isinstance(c, dict)]
    extras = {str(k): v for k, v in raw.items() if k not in known}
    if extras:
        node["extensions"] = normalize_mapping(extras)
    return node


def find_identifier(payload: dict[str, Any], fallback: str) -> tuple[str, str | None]:
    for field_name in IDENTIFIER_FIELDS:
        value = payload.get(field_name)
        if isinstance(value, str) and value:
            return value, field_name
    return fallback, None


def infer_release(root: Path) -> dict[str, Any]:
    changes = root / "CHANGES.md"
    text = changes.read_text(encoding="utf-8", errors="replace") if changes.exists() else ""
    versions = sorted(set(re.findall(r"(?:iOS|macOS|tvOS|visionOS|watchOS)\s+(\d+(?:\.\d+)*)", text)))
    return {"sourceDirectory": root.name, "versionsMentioned": versions[-10:], "changesSHA256": hashlib.sha256(text.encode()).hexdigest() if text else None}


def iter_schema_files(root: Path, families: Iterable[str]) -> Iterable[tuple[str, Path]]:
    for family in sorted(set(families)):
        rel = FAMILY_ROOTS.get(family)
        if not rel:
            continue
        base = root / rel
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.yaml")):
            if path.name.startswith("._"):
                continue
            yield family, path


def compile_schema(root: Path, options: CompileOptions) -> tuple[dict[str, Any], dict[str, Any], list[Diagnostic]]:
    root = root.resolve()
    diagnostics: list[Diagnostic] = []
    objects: list[dict[str, Any]] = []
    seen_ids: dict[tuple[str, str], str] = {}

    for family, path in iter_schema_files(root, options.families):
        rel = path.relative_to(root).as_posix()
        try:
            raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        except Exception as exc:
            diagnostics.append(Diagnostic("error", "yaml-parse", rel, str(exc)))
            continue
        if not isinstance(raw, dict):
            diagnostics.append(Diagnostic("warning", "non-object-schema", rel, "Top-level YAML is not an object; skipped."))
            continue
        payload = raw.get("payload") if isinstance(raw.get("payload"), dict) else {}
        identifier, identifier_field = find_identifier(payload, path.stem)
        identity = (family, identifier)
        if identity in seen_ids:
            diagnostics.append(Diagnostic("warning", "duplicate-identifier", rel, f"{family}:{identifier} was already defined by {seen_ids[identity]}."))
            object_id = f"{family}:{identifier}@{path.stem}"
        else:
            seen_ids[identity] = rel
            object_id = f"{family}:{identifier}"
        keys = raw.get("payloadkeys") or []
        if not isinstance(keys, list):
            diagnostics.append(Diagnostic("error", "invalid-payloadkeys", rel, "payloadkeys must be an array."))
            keys = []
        obj: dict[str, Any] = {
            "id": object_id,
            "family": family,
            "identifier": identifier,
            "identifierField": identifier_field,
            "title": clean_text(raw.get("title") or identifier),
            "description": clean_text(raw.get("description")) if raw.get("description") is not None else None,
            "source": rel,
            "payload": normalize_mapping(payload),
            "keys": [normalize_key(k, tuple(), diagnostics, rel) for k in keys if isinstance(k, dict)],
        }
        if options.include_examples and "examples" in raw:
            obj["examples"] = raw["examples"]
        extras = {str(k): v for k, v in raw.items() if k not in {"title", "description", "payload", "payloadkeys", "examples"}}
        if extras:
            obj["extensions"] = normalize_mapping(extras)
        objects.append(obj)

    objects.sort(key=lambda o: (o["family"], o["identifier"].lower(), o["source"]))
    by_id = {o["id"]: i for i, o in enumerate(objects)}
    by_identifier: dict[str, list[str]] = {}
    key_index: dict[str, list[dict[str, str]]] = {}
    lifecycle = {"deprecatedObjects": [], "removedObjects": [], "deprecatedKeys": [], "removedKeys": []}
    wildcard_count = 0
    key_count = 0

    def walk(obj: dict[str, Any], nodes: list[dict[str, Any]]) -> None:
        nonlocal wildcard_count, key_count
        for node in nodes:
            key_count += 1
            wildcard_count += 1 if node.get("wildcard") else 0
            key_index.setdefault(node["key"], []).append({"objectId": obj["id"], "path": node["pathString"]})
            support = node.get("supportedOS", {})
            if any(isinstance(v, dict) and v.get("deprecated") not in (None, "n/a") for v in support.values()): lifecycle["deprecatedKeys"].append({"objectId": obj["id"], "path": node["pathString"]})
            if any(isinstance(v, dict) and v.get("removed") not in (None, "n/a") for v in support.values()): lifecycle["removedKeys"].append({"objectId": obj["id"], "path": node["pathString"]})
            walk(obj, node.get("children", []))

    for obj in objects:
        by_identifier.setdefault(obj["identifier"], []).append(obj["id"])
        support = obj.get("payload", {}).get("supportedOS", {})
        if any(isinstance(v, dict) and v.get("deprecated") not in (None, "n/a") for v in support.values()): lifecycle["deprecatedObjects"].append(obj["id"])
        if any(isinstance(v, dict) and v.get("removed") not in (None, "n/a") for v in support.values()): lifecycle["removedObjects"].append(obj["id"])
        walk(obj, obj["keys"])

    generated = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    catalog = {
        "formatVersion": 1,
        "generatedAt": generated,
        "sourceRelease": infer_release(root),
        "families": sorted(options.families),
        "objects": objects,
    }
    index = {
        "formatVersion": 1,
        "generatedAt": generated,
        "objectCount": len(objects),
        "keyCount": key_count,
        "wildcardKeyCount": wildcard_count,
        "byId": by_id,
        "byIdentifier": {k: sorted(v) for k, v in sorted(by_identifier.items())},
        "keyIndex": {k: sorted(v, key=lambda x: (x["objectId"], x["path"])) for k, v in sorted(key_index.items())},
        "lifecycle": lifecycle,
    }
    return catalog, index, diagnostics


def write_outputs(output: Path, catalog: dict[str, Any], index: dict[str, Any], diagnostics: list[Diagnostic], pretty: bool = False) -> None:
    output.mkdir(parents=True, exist_ok=True)
    kwargs = {"ensure_ascii": False, "sort_keys": True, "indent": 2 if pretty else None, "separators": None if pretty else (",", ":")}
    (output / "apple-device-management-catalog.json").write_text(json.dumps(catalog, **kwargs) + "\n", encoding="utf-8")
    (output / "apple-device-management-index.json").write_text(json.dumps(index, **kwargs) + "\n", encoding="utf-8")
    report = {
        "generatedAt": catalog["generatedAt"],
        "summary": {
            "objects": index["objectCount"], "keys": index["keyCount"], "wildcards": index["wildcardKeyCount"],
            "errors": sum(d.severity == "error" for d in diagnostics), "warnings": sum(d.severity == "warning" for d in diagnostics),
        },
        "diagnostics": [d.as_dict() for d in diagnostics],
    }
    (output / "compile-report.json").write_text(json.dumps(report, **kwargs) + "\n", encoding="utf-8")
