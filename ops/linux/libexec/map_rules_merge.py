#!/usr/bin/env python3
"""Merge repository map rules without overwriting runtime overrides."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from vpk_campaigns import VpkError, parse_keyvalues, render_keyvalues


MISSING = object()


def read_rules(path: Path) -> dict:
    def convert(pairs):
        result = {}
        for key, value in pairs:
            key = key.casefold()
            if key in result:
                raise ValueError(f"{path}: duplicate key {key}")
            result[key] = convert(value) if isinstance(value, list) else value
        return result

    rules = convert(parse_keyvalues(path.read_text(encoding="utf-8-sig")))
    if set(rules) != {"maprules"} or not isinstance(rules["maprules"], dict):
        raise ValueError(f"{path}: expected MapRules root")
    return rules


def merge(base, current, incoming, path=""):
    if current == incoming or incoming == base:
        return current
    if current == base:
        return incoming
    if all(isinstance(value, dict) or value is MISSING for value in (base, current, incoming)):
        old, live, new = ({} if value is MISSING else value for value in (base, current, incoming))
        result = {}
        for key in dict.fromkeys([*live, *new, *old]):
            value = merge(old.get(key, MISSING), live.get(key, MISSING), new.get(key, MISSING), f"{path}/{key}")
            if value is not MISSING:
                result[key] = value
        return result if result or current is not MISSING else MISSING
    print(f"WARNING: map_rules.cfg conflict at {path}; keeping runtime value "
          f"{('<deleted>' if current is MISSING else repr(current))}", file=sys.stderr)
    return current


def pairs(value):
    return [(key, pairs(item) if isinstance(item, dict) else item) for key, item in value.items()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path)
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--incoming", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        incoming = read_rules(args.incoming)
        base = read_rules(args.base) if args.base else MISSING
        if not args.current.exists():
            args.output.write_bytes(args.incoming.read_bytes())
        else:
            current = read_rules(args.current)
            result = merge(base, current, incoming)
            if result == current:
                args.output.write_bytes(args.current.read_bytes())
            else:
                args.output.write_text(render_keyvalues(pairs(result)) + "\n", encoding="utf-8")
        return 0
    except (OSError, UnicodeError, ValueError, VpkError) as exc:
        print(f"map_rules_merge: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
