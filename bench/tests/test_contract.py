import copy
import json
from pathlib import Path

import jsonschema
import pytest

from itabench.models import EVENT_ADAPTER


def _lines(shared: Path) -> list[tuple[str, dict]]:
    out = []
    for f in sorted(shared.glob("fixtures/**/*.events.jsonl")):
        out.extend((f.name, json.loads(ln)) for ln in f.read_text().splitlines() if ln.strip())
    return out


def _schema(shared: Path) -> dict:
    return json.loads((shared / "engine-events.schema.json").read_text())


def test_fixtures_validate_and_parse(shared: Path) -> None:
    lines = _lines(shared)
    assert lines
    schema = _schema(shared)
    for name, obj in lines:
        jsonschema.validate(obj, schema)
        EVENT_ADAPTER.validate_python(obj)
        assert name


def test_model_dumps_validate_against_schema(shared: Path) -> None:
    schema = _schema(shared)
    for _, obj in _lines(shared):
        dumped = EVENT_ADAPTER.validate_python(obj).model_dump(mode="json", exclude_none=True)
        jsonschema.validate(dumped, schema)


def test_renamed_schema_field_breaks_fixtures(shared: Path) -> None:
    schema = copy.deepcopy(_schema(shared))
    for branch in schema["oneOf"]:
        props = branch["properties"]
        if "segment_id" in props:
            props["segment"] = props.pop("segment_id")
            branch["required"] = ["segment" if r == "segment_id" else r for r in branch["required"]]
    with pytest.raises(jsonschema.ValidationError):
        for _, obj in _lines(shared):
            jsonschema.validate(obj, schema)
