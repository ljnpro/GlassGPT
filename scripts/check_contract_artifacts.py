#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GENERATED_DIR = ROOT / "packages" / "backend-contracts" / "generated"


def main() -> int:
    openapi_path = GENERATED_DIR / "openapi.json"
    fixtures_path = GENERATED_DIR / "fixtures.json"

    missing = [path for path in (openapi_path, fixtures_path) if not path.is_file()]
    if missing:
        print("Contract artifact check failed.", file=sys.stderr)
        for path in missing:
            print(f"  missing {path.relative_to(ROOT)}", file=sys.stderr)
        return 1

    with openapi_path.open("r", encoding="utf-8") as handle:
        openapi_payload = json.load(handle)
    with fixtures_path.open("r", encoding="utf-8") as handle:
        fixtures_payload = json.load(handle)

    component_schemas = openapi_payload.get("components", {}).get("schemas", {})
    if not component_schemas:
        print("openapi.json does not contain component schemas", file=sys.stderr)
        return 1
    if not fixtures_payload:
        print("fixtures.json is empty", file=sys.stderr)
        return 1

    print("Contract artifact check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
