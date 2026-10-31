#!/usr/bin/env python3
"""Prepare campaign VPKs without changing their source files (standard library only)."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import struct
import sys
import tempfile
import zipfile
import zlib
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "vpk_campaigns", REPO / "ops/linux/libexec/vpk_campaigns.py"
)
assert SPEC is not None and SPEC.loader is not None
vpk = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = vpk
SPEC.loader.exec_module(vpk)


class PreparationError(ValueError):
    pass


@dataclass
class Token:
    text: str
    start: int
    end: int

    @property
    def key(self) -> str:
        return self.text.removeprefix('"').removesuffix('"').casefold()


@dataclass
class Node:
    key: Token
    value: Token | None = None
    children: list[Node] = field(default_factory=list)
    close: Token | None = None


TOKEN = re.compile(r'\s+|//[^\r\n]*|/\*.*?\*/|"[^"\r\n]*"|[{}]|[^\s{}"]+', re.S)


def tokenize(text: str) -> list[Token]:
    result = []
    end = 0
    for match in TOKEN.finditer(text):
        if match.start() != end:
            raise PreparationError("mission 引号或注释不完整，需人工检查")
        end = match.end()
        raw = match.group()
        if raw.isspace() or raw.startswith("//"):
            continue
        if raw.startswith("/*"):
            if not raw.endswith("*/"):
                raise PreparationError("mission 块注释未结束")
            continue
        result.append(Token(raw, match.start(), match.end()))
    if end != len(text):
        raise PreparationError("mission 文本不完整")
    return result


def parse_mission(text: str) -> tuple[Node, list[tuple[str, ...]], list[Token]]:
    tokens = tokenize(text)
    position = 0
    missing = []

    def read_node(path: tuple[str, ...]) -> Node:
        nonlocal position
        if position + 1 >= len(tokens):
            raise PreparationError("mission 字段缺少值")
        key, value = tokens[position : position + 2]
        position += 2
        if key.text in ("{", "}") or value.text == "}":
            raise PreparationError("mission 中间括号不匹配")
        node = Node(key)
        if value.text != "{":
            node.value = value
            return node
        current = (*path, key.key)
        while position < len(tokens):
            if tokens[position].text == "}":
                node.close = tokens[position]
                position += 1
                return node
            node.children.append(read_node(current))
        missing.append(current)
        return node

    root = read_node(())
    if root.key.key != "mission" or root.value is not None:
        raise PreparationError("需要唯一的 mission 根对象")
    extra = tokens[position:]
    if any(token.text != "}" for token in extra):
        raise PreparationError("mission 根对象后存在其他字段，不能自动修复")
    return root, missing, extra


def child(node: Node, name: str, required: bool = True) -> Node | None:
    found = [item for item in node.children if item.key.key == name]
    if len(found) > 1 or (required and not found):
        raise PreparationError(f"mission 的 {name} 字段缺失或重复")
    return found[0] if found else None


def validate(root: Node, repairing_tail: bool = False) -> Node:
    modes = child(root, "modes")
    assert modes is not None
    if modes.value is not None or not modes.children:
        raise PreparationError("modes 不是有效对象")
    names = [mode.key.key for mode in modes.children]
    if len(names) != len(set(names)):
        raise PreparationError("modes 中存在重复模式")
    for mode in modes.children:
        if mode.value is not None:
            raise PreparationError(f"{mode.key.text} 模式不是对象")
        if mode.key.key not in ("coop", "versus") and not repairing_tail:
            continue
        chapters = [entry.key.key for entry in mode.children]
        if chapters != [str(index) for index in range(1, len(chapters) + 1)] or not chapters:
            raise PreparationError(f"{mode.key.text} 章节必须从 1 连续排列；可能存在中间括号错误")
        for chapter in mode.children:
            map_node = child(chapter, "map")
            if chapter.value is not None or map_node is None or map_node.value is None:
                raise PreparationError("章节缺少 Map，可能存在中间括号错误")
    return modes


def decode(data: bytes) -> tuple[str, str]:
    encodings = ["utf-16"] if data.startswith((b"\xff\xfe", b"\xfe\xff")) else []
    encodings += ["utf-8-sig" if data.startswith(b"\xef\xbb\xbf") else "utf-8", "gb18030", "latin-1"]
    for encoding in encodings:
        try:
            text = data.decode(encoding)
            if text.encode(encoding) == data:
                return text, encoding
        except UnicodeError:
            pass
    raise PreparationError("无法无损解码 mission")


def prepare_mission(data: bytes) -> tuple[bytes, list[str]]:
    text, encoding = decode(data)
    root, missing, extra = parse_mission(text)
    # During repair, every presumed mode must actually be a chapter list. This
    # rejects a missing middle brace that swallowed a root-level poster object.
    validate(root, repairing_tail=bool(missing))
    if any(path not in (("mission",), ("mission", "modes")) for path in missing):
        raise PreparationError("未闭合对象位于章节或其他字段内，不能确定只缺末尾括号")
    actions = []
    newline = "\r\n" if "\r\n" in text else "\n"
    for token in reversed(extra):
        text = text[: token.start] + text[token.end :]
    if extra:
        actions.append(f"移除末尾多余闭合括号 {len(extra)} 个")
    if missing:
        text += newline + ("}" + newline) * len(missing)
        actions.append(f"补齐末尾闭合括号 {len(missing)} 个")
    root, missing, extra = parse_mission(text)
    if missing or extra:
        raise PreparationError("括号修复后结构仍不完整")
    modes = validate(root)
    if child(modes, "versus", required=False) is None:
        coop = child(modes, "coop", required=False)
        if coop is None:
            result = text.encode(encoding) if actions else data
            return result, [*actions, "无 coop，未补 versus"]
        assert coop.close is not None and modes.close is not None
        # Keep the complete original block, including comments and literal backslashes.
        block = '"versus"' + text[coop.key.end : coop.close.end]
        insertion = newline + "\t\t" + block + newline + "\t"
        text = text[: modes.close.start] + insertion + text[modes.close.start :]
        actions.append("复制 coop 为 versus")
    if not actions:
        return data, []
    root, missing, extra = parse_mission(text)
    if missing or extra:
        raise PreparationError("修改后的 mission 结构不完整")
    validate(root)
    return text.encode(encoding), actions


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare_vpk(source: Path, destination: Path) -> list[dict[str, object]]:
    entries = []
    replacements = {}
    hashes = {}
    missions = []
    for entry, data in vpk.iter_vpk_entries(source):
        if entry.archive_index != vpk.VPK_EMBEDDED_ARCHIVE and entry.length:
            raise PreparationError("暂不处理分卷 VPK；需要完整的单文件包")
        normalized = entry.path.casefold()
        if normalized in hashes:
            raise PreparationError(f"包内重复路径：{entry.path}")
        hashes[normalized] = hashlib.sha256(data).digest()
        if normalized.startswith("missions/") and normalized.endswith(".txt"):
            updated, actions = prepare_mission(data)
            if updated != data:
                replacements[entry.path] = updated
            missions.append({"path": entry.path, "actions": actions})
        entries.append((entry, len(data)))
    if not entries:
        raise PreparationError("VPK 为空")
    if not replacements:
        shutil.copyfile(source, destination)
        return missions

    # Rebuild compactly, rather than retaining superseded mission payloads.
    groups: dict[str, dict[str, list[tuple[object, int, str]]]] = {}
    for entry, length in entries:
        directory, _, filename = entry.path.rpartition("/")
        name, dot, extension = filename.rpartition(".")
        if not dot:
            name, extension = filename, " "
        groups.setdefault(extension, {}).setdefault(directory or " ", []).append((entry, length, name))
    tree = bytearray()
    offset = 0
    ordered = []
    for extension, directories in groups.items():
        tree.extend(extension.encode("utf-8", errors="surrogateescape") + b"\0")
        for directory, items in directories.items():
            tree.extend(directory.encode("utf-8", errors="surrogateescape") + b"\0")
            for entry, length, name in items:
                replacement = replacements.get(entry.path)
                crc = entry.crc32 if replacement is None else zlib.crc32(replacement)
                length = length if replacement is None else len(replacement)
                tree.extend(name.encode("utf-8", errors="surrogateescape") + b"\0")
                tree.extend(struct.pack("<IHHIIH", crc, 0, 32767, offset, length, 65535))
                ordered.append(entry.path)
                offset += length
            tree.extend(b"\0")
        tree.extend(b"\0")
    tree.extend(b"\0")
    if ordered != [entry.path for entry, _ in entries]:
        raise PreparationError("源 VPK 目录排序异常")
    with destination.open("wb") as output:
        output.write(struct.pack("<III", vpk.VPK_SIGNATURE, 1, len(tree)))
        output.write(tree)
        for entry, data in vpk.iter_vpk_entries(source):
            output.write(replacements.get(entry.path, data))
    # Re-read the entire generated archive: CRCs, paths and unchanged bytes.
    checked = set()
    for entry, data in vpk.iter_vpk_entries(destination):
        expected = replacements.get(entry.path)
        expected_hash = (
            hashes[entry.path.casefold()]
            if expected is None
            else hashlib.sha256(expected).digest()
        )
        if hashlib.sha256(data).digest() != expected_hash:
            raise PreparationError(f"输出校验失败：{entry.path}")
        checked.add(entry.path.casefold())
    if checked != set(hashes):
        raise PreparationError("输出文件列表与原包不一致")
    return missions


def unpack(source: Path, scratch: Path) -> list[tuple[Path, str]]:
    with source.open("rb") as stream:
        magic = stream.read(4)
    if magic == struct.pack("<I", vpk.VPK_SIGNATURE):
        return [(source, source.name)]
    if not zipfile.is_zipfile(source):
        raise PreparationError("不是有效的 VPK 或 ZIP")
    with zipfile.ZipFile(source) as archive:
        members = [
            entry
            for entry in archive.infolist()
            if not entry.is_dir() and entry.filename.casefold().endswith(".vpk")
        ]
        if not members:
            raise PreparationError("ZIP 中没有 VPK")
        names = [Path(member.filename.replace("\\", "/")).name for member in members]
        if len(set(name.casefold() for name in names)) != len(names):
            raise PreparationError("ZIP 内有同名 VPK，无法平铺输出")
        results = []
        for index, (member, name) in enumerate(zip(members, names)):
            target = scratch / f"unpacked-{index}.vpk"
            with archive.open(member) as incoming, target.open("wb") as outgoing:
                shutil.copyfileobj(incoming, outgoing)
            results.append((target, name))
        return results


def main() -> int:
    parser = argparse.ArgumentParser(description="补齐地图 versus，修复明确的末尾括号；原包不变。")
    parser.add_argument("inputs", nargs="+", type=Path, help="VPK、ZIP 或文件夹（仅扫描顶层 .vpk）")
    parser.add_argument("--output", type=Path, help="成品目录；默认输入旁的 prepared-vpks")
    parser.add_argument("--overwrite", action="store_true", help="允许替换成品目录中内容不同的同名文件")
    args = parser.parse_args()
    sources = []
    for supplied in args.inputs:
        supplied = supplied.resolve()
        if supplied.is_dir():
            sources.extend(
                (path, supplied / "prepared-vpks")
                for path in sorted(supplied.iterdir())
                if path.is_file() and path.suffix.casefold() == ".vpk"
            )
        else:
            sources.append((supplied, supplied.parent / "prepared-vpks"))
    sources = list(dict.fromkeys(sources))
    source_paths = {source for source, _ in sources}
    if not sources:
        parser.error("输入目录顶层没有 VPK")
    scratch_root = REPO / ".tmp"
    scratch_root.mkdir(exist_ok=True)
    claimed: set[Path] = set()
    results = []
    failed = False
    for source, default_output in sources:
        output = (args.output or default_output).resolve()
        try:
            with tempfile.TemporaryDirectory(
                prefix=datetime.now().strftime("%Y%m%d-vpk-prepare-"),
                dir=scratch_root,
            ) as temporary:
                scratch = Path(temporary)
                packages = unpack(source, scratch)
                for index, (package, name) in enumerate(packages):
                    target = output / name
                    if target in source_paths or target in claimed:
                        raise PreparationError(f"输出路径与输入或另一成品冲突：{target}")
                    claimed.add(target)
                    candidate = scratch / f"prepared-{index}.vpk"
                    missions = prepare_vpk(package, candidate)
                    checksum = digest(candidate)
                    status = "已生成"
                    if target.exists():
                        if digest(target) == checksum:
                            status = "已相同，跳过"
                        elif not args.overwrite:
                            raise PreparationError(f"成品已存在且内容不同：{target}；确认后使用 --overwrite")
                    if status == "已生成":
                        output.mkdir(parents=True, exist_ok=True)
                        shutil.copyfile(candidate, target)
                        if digest(target) != checksum:
                            raise PreparationError(f"写入后校验失败：{target}")
                    result = {
                        "source": str(source),
                        "output": str(target),
                        "status": status,
                        "sha256": checksum,
                        "missions": missions,
                    }
                    results.append(result)
                    print(f"{status}：{name}（{len(missions)} 份 mission）", flush=True)
                    for mission in missions:
                        if mission["actions"]:
                            details = "；".join(mission["actions"])
                            print(f"  {mission['path']}：{details}", flush=True)
        except (OSError, ValueError, RuntimeError, struct.error, zipfile.BadZipFile) as error:
            failed = True
            results.append({"source": str(source), "error": str(error)})
            print(f"需检查：{source.name}：{error}", file=sys.stderr, flush=True)
    # A report accompanies each destination, including failures from this run.
    for output in {(args.output or default).resolve() for _, default in sources}:
        if output.is_dir():
            (output / "preparation-report.json").write_text(
                json.dumps(results, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
