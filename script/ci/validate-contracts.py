#!/usr/bin/env python3
"""Port the approved pack's contract checks; this never executes application code."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import re

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "docs/agent-native/contracts"
OUT = ROOT / "tmp/wp01"


def load(name):
    return json.loads((CONTRACTS / name).read_text(encoding="utf-8"))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def convert(value):
    if isinstance(value, dict):
        return {k: (v.replace("#/$defs/", "#/components/schemas/") if k == "$ref" else convert(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [convert(item) for item in value]
    return value


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def pointer(document, ref):
    assert ref.startswith("#/"), f"Nonlocal reference: {ref}"
    for part in ref[2:].split("/"):
        document = document[part.replace("~1", "/").replace("~0", "~")]
    return document


schemas = load("schemas.json")
catalog = load("openapi-catalog.json")
fixtures = load("fixtures.json")
operations = load("operations.json")
machines = load("state-machines.json")
freeze = load("freeze.json")
api = copy.deepcopy(catalog["header"])
api["paths"] = {}
for entry in catalog["operations"]:
    human = entry["human_only"]
    security = ([{"HumanSession": [], "CsrfToken": []}] if entry["method"] != "GET" else [{"HumanSession": []}]) if human else [{"AgentBearer": []}]
    operation = {
        "operationId": entry["operation_id"], "summary": entry["summary"],
        "description": entry.get("description", entry["summary"]), "security": security,
        "parameters": entry["parameters"], "responses": {**entry["success"], "default": catalog["default_error"]},
        "x-required-scopes": entry["scopes"], "x-durable-mutation": entry["durable"], "x-human-only": human,
    }
    if "request_body" in entry:
        operation["requestBody"] = entry["request_body"]
    api["paths"].setdefault(entry["path"], {})[entry["method"].lower()] = operation
api["components"] = {"securitySchemes": catalog["security_schemes"], "schemas": convert(schemas["$defs"])}

checks = []


def check(name, condition):
    checks.append({"name": name, "passed": bool(condition)})
    if not condition:
        raise AssertionError(name)


for name, value in {"schemas.json": schemas, "openapi.yaml": api, "fixtures.json": fixtures, "operations.json": operations, "state-machines.json": machines}.items():
    check(f"Frozen source semantic hash: {name}", hashlib.sha256(canonical(value)).hexdigest() == freeze["canonical_sha256"][name])
check("OpenAPI version", api["openapi"] == "3.1.1")
for name, schema in schemas["$defs"].items():
    Draft202012Validator.check_schema(schema)
for document in (schemas, api):
    for node in walk(document):
        if "$ref" in node:
            pointer(document, node["$ref"])
check("All schemas are structurally valid and references resolve", True)

fixture_results = []
for fixture in fixtures["fixtures"]:
    wrapper = {"$schema": schemas["$schema"], "$defs": schemas["$defs"], "$ref": f"#/$defs/{fixture['schema']}"}
    valid = Draft202012Validator(wrapper, format_checker=FormatChecker()).is_valid(fixture["data"])
    check(f"Fixture: {fixture['name']}", valid == fixture["valid"])
    fixture_results.append({"name": fixture["name"], "expected_valid": fixture["valid"], "actual_valid": valid})

seen = set()
observed = set()
for path, methods in api["paths"].items():
    for method, operation in methods.items():
        oid = operation["operationId"]
        check(f"Unique operation ID: {oid}", oid not in seen)
        seen.add(oid)
        observed.add((path, method.upper(), oid))
        parameters = operation["parameters"]
        expected = set(re.findall(r"\{([^}]+)\}", path))
        actual = {p["name"] for p in parameters if p["in"] == "path" and p["required"]}
        check(f"Path parameters: {oid}", expected == actual)
        headers = {p["name"] for p in parameters if p["in"] == "header" and p.get("required")}
        check(f"Durable idempotency: {oid}", not operation["x-durable-mutation"] or "Idempotency-Key" in headers)
        human = operation["x-human-only"]
        expected_security = ([{"HumanSession": [], "CsrfToken": []}] if method != "get" else [{"HumanSession": []}]) if human else [{"AgentBearer": []}]
        check(f"Authentication boundary: {oid}", operation["security"] == expected_security)
        check(f"Sanitized error contract: {oid}", "default" in operation["responses"])
check("Operation inventory", observed == {(o["path"], o["method"], o["operation_id"]) for o in operations})

for name, machine in machines["machines"].items():
    states = set(machine["transitions"])
    check(f"Known initial and terminal states: {name}", set(machine["initial"]).issubset(states) and set(machine["terminal"]).issubset(states))
    for state, following in machine["transitions"].items():
        check(f"Known transitions: {name}/{state}", set(following).issubset(states))
        check(f"Closed terminal: {name}/{state}", state not in machine["terminal"] or not following)

OUT.mkdir(parents=True, exist_ok=True)
(OUT / "openapi.json").write_text(json.dumps(api, indent=2) + "\n")
report = {"scope": "Documentation validation only; not endpoint or product qualification", "full_openapi_specification_validator": False,
          "schema_count": len(schemas["$defs"]), "operation_count": len(operations), "fixture_count": len(fixture_results), "checks": checks}
(OUT / "contract-report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: {len(schemas['$defs'])} schemas, {len(operations)} operations, {len(fixture_results)} fixtures, {len(checks)} documentation checks.")
print("Assembled OpenAPI: tmp/wp01/openapi.json. Native endpoints remain unimplemented.")
