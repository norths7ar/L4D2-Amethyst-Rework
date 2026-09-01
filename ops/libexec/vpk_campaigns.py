#!/usr/bin/env python3
"""Inspect campaign VPKs and reconcile Campaign Switcher's mission cycle."""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Iterator, TypeAlias


VPK_SIGNATURE = 0x55AA1234
VPK_EMBEDDED_ARCHIVE = 0x7FFF
CHUNK_NAME = re.compile(r"_\d{3}\.vpk$", re.IGNORECASE)
KVValue: TypeAlias = str | list[tuple[str, "KVValue"]]


class VpkError(RuntimeError):
    pass


@dataclass(frozen=True)
class VpkEntry:
    path: str
    archive_index: int
    offset: int
    length: int
    preload: bytes


def read_cstring(stream: BinaryIO) -> str:
    data = bytearray()
    while True:
        byte = stream.read(1)
        if not byte:
            raise VpkError("unexpected end of VPK directory tree")
        if byte == b"\0":
            return data.decode("utf-8", errors="surrogateescape")
        data.extend(byte)


def iter_vpk_entries(vpk_path: Path) -> Iterator[tuple[VpkEntry, bytes]]:
    with vpk_path.open("rb") as stream:
        header = stream.read(12)
        if len(header) != 12:
            raise VpkError(f"{vpk_path.name}: truncated VPK header")
        signature, version, tree_size = struct.unpack("<III", header)
        if signature != VPK_SIGNATURE:
            raise VpkError(f"{vpk_path.name}: invalid VPK signature")
        if version == 1:
            header_size = 12
        elif version == 2:
            remainder = stream.read(16)
            if len(remainder) != 16:
                raise VpkError(f"{vpk_path.name}: truncated VPK v2 header")
            header_size = 28
        else:
            raise VpkError(f"{vpk_path.name}: unsupported VPK version {version}")

        tree_end = header_size + tree_size
        while True:
            extension = read_cstring(stream)
            if not extension:
                break
            while True:
                directory = read_cstring(stream)
                if not directory:
                    break
                while True:
                    filename = read_cstring(stream)
                    if not filename:
                        break
                    raw_entry = stream.read(18)
                    if len(raw_entry) != 18:
                        raise VpkError(f"{vpk_path.name}: truncated VPK entry")
                    _, preload_size, archive_index, offset, length, terminator = struct.unpack(
                        "<IHHIIH", raw_entry
                    )
                    if terminator != 0xFFFF:
                        raise VpkError(f"{vpk_path.name}: invalid VPK entry terminator")
                    preload = stream.read(preload_size)
                    if len(preload) != preload_size:
                        raise VpkError(f"{vpk_path.name}: truncated preload data")

                    path_parts = [] if directory == " " else [directory]
                    path_parts.append(filename if extension == " " else f"{filename}.{extension}")
                    entry = VpkEntry(
                        path="/".join(path_parts).replace("\\", "/"),
                        archive_index=archive_index,
                        offset=offset,
                        length=length,
                        preload=preload,
                    )
                    normalized_path = entry.path.casefold()
                    if normalized_path.startswith("missions/") and normalized_path.endswith(".txt"):
                        payload = read_entry_data(vpk_path, stream, tree_end, entry)
                    else:
                        payload = b""
                    yield entry, payload


def read_entry_data(vpk_path: Path, directory_stream: BinaryIO, tree_end: int, entry: VpkEntry) -> bytes:
    if entry.length == 0:
        return entry.preload

    if entry.archive_index == VPK_EMBEDDED_ARCHIVE:
        current = directory_stream.tell()
        directory_stream.seek(tree_end + entry.offset)
        payload = directory_stream.read(entry.length)
        directory_stream.seek(current)
    else:
        base_name = vpk_path.name
        if base_name.lower().endswith("_dir.vpk"):
            base_name = base_name[:-8]
        else:
            base_name = vpk_path.stem
        archive_path = vpk_path.with_name(f"{base_name}_{entry.archive_index:03d}.vpk")
        try:
            with archive_path.open("rb") as archive:
                archive.seek(entry.offset)
                payload = archive.read(entry.length)
        except FileNotFoundError as error:
            raise VpkError(f"{vpk_path.name}: missing archive chunk {archive_path.name}") from error

    if len(payload) != entry.length:
        raise VpkError(f"{vpk_path.name}: truncated payload for {entry.path}")
    return entry.preload + payload


def decode_text(data: bytes, source: str) -> str:
    encodings = ["utf-8-sig"]
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        encodings.insert(0, "utf-16")
    encodings.extend(["gb18030", "latin-1"])
    for encoding in encodings:
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise VpkError(f"{source}: unsupported text encoding")


def tokenize_keyvalues(text: str) -> Iterator[str]:
    index = 0
    length = len(text)
    while index < length:
        if text[index].isspace():
            index += 1
            continue
        if text.startswith("//", index):
            newline = text.find("\n", index + 2)
            index = length if newline == -1 else newline + 1
            continue
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end == -1:
                raise VpkError("unterminated KeyValues block comment")
            index = end + 2
            continue
        if text[index] in "{}":
            yield text[index]
            index += 1
            continue
        if text[index] == '"':
            index += 1
            token = []
            while index < length:
                char = text[index]
                if char == '"':
                    index += 1
                    break
                if char == "\\" and index + 1 < length:
                    escaped = text[index + 1]
                    token.append({"n": "\n", "t": "\t"}.get(escaped, escaped))
                    index += 2
                    continue
                token.append(char)
                index += 1
            else:
                raise VpkError("unterminated KeyValues string")
            yield "".join(token)
            continue

        end = index
        while end < length and not text[end].isspace() and text[end] not in '{}"':
            end += 1
        yield text[index:end]
        index = end


def parse_keyvalues(text: str) -> list[tuple[str, KVValue]]:
    tokens = iter(tokenize_keyvalues(text))

    def parse_object(expect_close: bool) -> list[tuple[str, KVValue]]:
        values: list[tuple[str, KVValue]] = []
        for key in tokens:
            if key == "}":
                if not expect_close:
                    raise VpkError("unexpected closing brace in KeyValues")
                return values
            if key == "{":
                raise VpkError("unexpected opening brace in KeyValues")
            try:
                value = next(tokens)
            except StopIteration as error:
                raise VpkError(f"missing value for KeyValues key {key!r}") from error
            if value == "{":
                values.append((key, parse_object(True)))
            elif value == "}":
                raise VpkError(f"missing value for KeyValues key {key!r}")
            else:
                values.append((key, value))
        if expect_close:
            raise VpkError("unterminated KeyValues object")
        return values

    return parse_object(False)


def find_pair(pairs: list[tuple[str, KVValue]], key: str) -> KVValue | None:
    wanted = key.casefold()
    for name, value in pairs:
        if name.casefold() == wanted:
            return value
    return None


def scalar(pairs: list[tuple[str, KVValue]], key: str) -> str | None:
    value = find_pair(pairs, key)
    return value if isinstance(value, str) else None


def mission_campaign(mission_path: str, data: bytes, source_name: str) -> dict[str, object] | None:
    root = parse_keyvalues(decode_text(data, f"{source_name}:{mission_path}"))
    mission_value = find_pair(root, "mission")
    mission = mission_value if isinstance(mission_value, list) else root
    modes_value = find_pair(mission, "modes")
    if not isinstance(modes_value, list):
        return None

    mode: list[tuple[str, KVValue]] | None = None
    coop_value = find_pair(modes_value, "coop")
    if isinstance(coop_value, list):
        mode = coop_value
    else:
        for _, candidate in modes_value:
            if isinstance(candidate, list):
                mode = candidate
                break
    if mode is None:
        return None

    maps: list[str] = []
    for _, chapter_value in mode:
        if not isinstance(chapter_value, list):
            continue
        map_name = scalar(chapter_value, "Map")
        if map_name:
            maps.append(map_name)
    if not maps:
        return None

    display_title = scalar(mission, "DisplayTitle") or scalar(mission, "Name") or Path(source_name).stem
    if display_title.startswith("#"):
        display_title = scalar(mission, "Name") or Path(source_name).stem
    return {
        "source": source_name,
        "mission": mission_path,
        "first_map": maps[0],
        "maps": maps,
        "name": display_title,
    }


def inspect_directory(directory: Path) -> dict[str, object]:
    if not directory.is_dir():
        raise VpkError(f"VPK directory does not exist: {directory}")

    all_vpks = sorted(directory.glob("*.vpk"), key=lambda path: path.name.casefold())
    primary_vpks = [path for path in all_vpks if not CHUNK_NAME.search(path.name)]
    chunk_names = {path.name for path in all_vpks if CHUNK_NAME.search(path.name)}
    referenced_chunks: set[str] = set()
    campaigns: list[dict[str, object]] = []

    for vpk_path in primary_vpks:
        for entry, data in iter_vpk_entries(vpk_path):
            if entry.archive_index != VPK_EMBEDDED_ARCHIVE:
                base_name = vpk_path.name[:-8] if vpk_path.name.lower().endswith("_dir.vpk") else vpk_path.stem
                referenced_chunks.add(f"{base_name}_{entry.archive_index:03d}.vpk")
            normalized = entry.path.casefold()
            if normalized.startswith("missions/") and normalized.endswith(".txt"):
                campaign = mission_campaign(entry.path, data, vpk_path.name)
                if campaign:
                    campaigns.append(campaign)

    orphaned_chunks = sorted(chunk_names - referenced_chunks, key=str.casefold)
    if orphaned_chunks:
        raise VpkError(f"orphaned VPK archive chunks: {', '.join(orphaned_chunks)}")

    seen_maps: dict[str, str] = {}
    for campaign in campaigns:
        for map_name in campaign["maps"]:
            normalized = str(map_name).casefold()
            previous = seen_maps.get(normalized)
            if previous:
                raise VpkError(
                    f"map {map_name!r} is declared more than once by {previous!r} and {campaign['source']!r}"
                )
            seen_maps[normalized] = str(campaign["source"])

    campaigns.sort(key=lambda item: (str(item["name"]).casefold(), str(item["first_map"]).casefold()))
    return {
        "files": [path.name for path in all_vpks],
        "campaigns": campaigns,
    }


def escape_keyvalues(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def render_keyvalues(pairs: list[tuple[str, KVValue]], indent: int = 0) -> str:
    lines: list[str] = []
    prefix = "\t" * indent
    for key, value in pairs:
        lines.append(f'{prefix}"{escape_keyvalues(key)}"')
        if isinstance(value, list):
            lines.append(f"{prefix}{{")
            lines.append(render_keyvalues(value, indent + 1))
            lines.append(f"{prefix}}}")
        else:
            lines[-1] += f'\t"{escape_keyvalues(value)}"'
    return "\n".join(lines)


def reconcile_missioncycle(source_path: Path, inventory_path: Path, output_path: Path, section: str) -> None:
    root = parse_keyvalues(source_path.read_text(encoding="utf-8-sig"))
    mission_cycle_value = find_pair(root, "MissionCycle")
    if not isinstance(mission_cycle_value, list):
        raise VpkError(f"{source_path}: missing MissionCycle root")

    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    campaigns = inventory.get("campaigns")
    if not isinstance(campaigns, list):
        raise VpkError(f"{inventory_path}: invalid campaign inventory")

    existing_names: dict[str, str] = {}
    existing_order: dict[str, int] = {}
    section_index: int | None = None
    for index, (name, value) in enumerate(mission_cycle_value):
        if name == section and isinstance(value, list):
            section_index = index
            for position, (first_map, details) in enumerate(value):
                existing_order[first_map.casefold()] = position
                if isinstance(details, list):
                    existing_name = scalar(details, "name")
                    if existing_name:
                        existing_names[first_map.casefold()] = existing_name
            break

    def campaign_order(campaign: dict[str, object]) -> tuple[int, int | str, str]:
        first_map = str(campaign["first_map"])
        normalized = first_map.casefold()
        if normalized in existing_order:
            return (0, existing_order[normalized], normalized)
        return (1, str(campaign["name"]).casefold(), normalized)

    campaigns.sort(key=campaign_order)
    managed_section: list[tuple[str, KVValue]] = []
    seen_first_maps: set[str] = set()
    for campaign in campaigns:
        first_map = str(campaign["first_map"])
        normalized = first_map.casefold()
        if normalized in seen_first_maps:
            raise VpkError(f"duplicate campaign first map: {first_map}")
        seen_first_maps.add(normalized)
        display_name = existing_names.get(normalized, str(campaign["name"]))
        managed_section.append((first_map, [("name", display_name)]))

    replacement: tuple[str, KVValue] = (section, managed_section)
    if section_index is None:
        mission_cycle_value.append(replacement)
    else:
        mission_cycle_value[section_index] = replacement

    output_path.write_text(render_keyvalues(root) + "\n", encoding="utf-8", newline="\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    inventory = subparsers.add_parser("inventory", help="validate VPKs and emit campaign JSON")
    inventory.add_argument("directory", type=Path)
    inventory.add_argument("--output", type=Path)

    reconcile = subparsers.add_parser("reconcile", help="replace the managed mission-cycle section")
    reconcile.add_argument("--source", required=True, type=Path)
    reconcile.add_argument("--inventory", required=True, type=Path)
    reconcile.add_argument("--output", required=True, type=Path)
    reconcile.add_argument("--section", default="第三方战役")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "inventory":
            result = inspect_directory(args.directory)
            serialized = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
            if args.output:
                args.output.write_text(serialized, encoding="utf-8", newline="\n")
            else:
                sys.stdout.write(serialized)
        else:
            reconcile_missioncycle(args.source, args.inventory, args.output, args.section)
    except (OSError, ValueError, VpkError) as error:
        print(f"vpk_campaigns: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
