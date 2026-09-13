from __future__ import annotations

import importlib.util
import json
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "libexec" / "vpk_campaigns.py"
SPEC = importlib.util.spec_from_file_location("vpk_campaigns", MODULE_PATH)
assert SPEC and SPEC.loader
VPK = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VPK
SPEC.loader.exec_module(VPK)


def write_single_file_vpk(
    path: Path, internal_path: str, payload: bytes, *, corrupt_crc: bool = False
) -> None:
    write_files_vpk(
        path,
        [(internal_path, payload, corrupt_crc)],
    )


def write_files_vpk(
    path: Path, files: list[tuple[str, bytes, bool]]
) -> None:
    grouped: dict[str, dict[str, list[tuple[str, bytes, bool]]]] = {}
    for internal_path, payload, corrupt_crc in files:
        directory, leaf = internal_path.rsplit("/", 1)
        filename, extension = leaf.rsplit(".", 1)
        grouped.setdefault(extension, {}).setdefault(directory, []).append(
            (filename, payload, corrupt_crc)
        )

    tree = bytearray()
    payloads = bytearray()
    for extension, directories in grouped.items():
        tree.extend(extension.encode() + b"\0")
        for directory, entries in directories.items():
            tree.extend(directory.encode() + b"\0")
            for filename, payload, corrupt_crc in entries:
                crc32 = zlib.crc32(payload) & 0xFFFFFFFF
                if corrupt_crc:
                    crc32 ^= 0xFFFFFFFF
                tree.extend(filename.encode() + b"\0")
                tree.extend(
                    struct.pack(
                        "<IHHIIH",
                        crc32,
                        0,
                        0x7FFF,
                        len(payloads),
                        len(payload),
                        0xFFFF,
                    )
                )
                payloads.extend(payload)
            tree.extend(b"\0")
        tree.extend(b"\0")
    tree.extend(b"\0")
    header = struct.pack("<III", 0x55AA1234, 1, len(tree))
    path.write_bytes(header + tree + payloads)


def mission(
    first_map: str = "example_m1",
    second_map: str = "example_m2",
    *,
    include_versus: bool = True,
) -> bytes:
    versus = f'''
        "versus"
        {{
            "1" {{ "Map" "{first_map}" }}
            "2" {{ "Map" "{second_map}" }}
        }}''' if include_versus else ""
    return f'''"mission"
{{
    "Name" "Example Campaign"
    "DisplayTitle" "Example Display"
    "modes"
    {{
        "coop"
        {{
            "1" {{ "Map" "{first_map}" }}
            "2" {{ "Map" "{second_map}" }}
        }}
{versus}
    }}
}}
'''.encode()


class VpkCampaignTests(unittest.TestCase):
    def test_reconcile_curated_prefix_and_persistent_append_history(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            live = directory / "live.txt"
            policy = directory / "policy.txt"
            inventory = directory / "inventory.json"

            def write_policy(order: str) -> None:
                entries = [(letter, [("name", "仓库" + letter)]) for letter in order]
                policy.write_text(VPK.render_keyvalues([("MissionCycle", [
                    ("官方战役", [("official", [("name", "官图")])]),
                    ("第三方战役", entries),
                ])]), encoding="utf-8")

            def reconcile(installed: str) -> list[tuple[str, object]]:
                # Reverse title order deliberately: new batch sorting must not
                # reorder an earlier batch, regardless of inventory order.
                inventory.write_text(json.dumps({"campaigns": [
                    {"first_map": c, "name": str(100 - ord(c))} for c in installed
                ]}), encoding="utf-8")
                VPK.reconcile_missioncycle(live, inventory, live, "第三方战役", policy)
                root = VPK.find_pair(VPK.parse_keyvalues(live.read_text(encoding="utf-8")), "MissionCycle")
                self.assertEqual(VPK.find_pair(root, "官方战役"), [("official", [("name", "官图")])])
                return VPK.find_pair(root, "第三方战役")

            write_policy("HIJKLMN")
            live.write_bytes(policy.read_bytes())
            self.assertEqual([k for k, _ in reconcile("HIJKLMNABC")], list("HIJKLMNCBA"))
            self.assertEqual([k for k, _ in reconcile("HIJKLMNABCDEF")], list("HIJKLMNCBAFED"))
            write_policy("HIJKFLMN")
            entries = reconcile("HIJKLMNABCDEF")
            self.assertEqual([k for k, _ in entries], list("HIJKFLMNCBAED"))
            self.assertEqual(dict(entries)["F"], [("name", "仓库F")])
            self.assertEqual(entries, reconcile("FEDCBANMLKJIH"))
            # Removed VPKs disappear even when curated; returning maps append.
            self.assertEqual([k for k, _ in reconcile("HIJKLMNABDE")], list("HIJKLMNBAED"))
            self.assertEqual([k for k, _ in reconcile("HIJKLMNABCDE")], list("HIJKLMNBAEDC"))

    def test_cache_invalidates_when_archive_chunk_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            cache = directory / "cache.json"
            primary = directory / "example_dir.vpk"
            chunk = directory / "example_000.vpk"
            payload = mission()
            write_single_file_vpk(primary, "missions/example.txt", payload)
            data = bytearray(primary.read_bytes())
            tree_end = 12 + struct.unpack_from("<I", data, 8)[0]
            entry_offset = 12 + len(b"txt\0missions\0example\0")
            struct.pack_into("<H", data, entry_offset + 6, 0)
            primary.write_bytes(data[:tree_end])
            chunk.write_bytes(payload)
            VPK.inspect_directory(directory, cache)
            with patch.object(VPK, "iter_vpk_entries", side_effect=AssertionError("read unchanged VPK")):
                VPK.inspect_directory(directory, cache)
            chunk.write_bytes(payload.replace(b"Example Display", b"Changed Display") + b"\n")
            with self.assertRaisesRegex(VPK.VpkError, "CRC mismatch"):
                VPK.inspect_directory(directory, cache)

    def test_cache_reuses_unchanged_and_checks_changed_added_deleted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            cache = directory / "cache.json"
            first = directory / "first.vpk"
            write_single_file_vpk(first, "missions/first.txt", mission())
            expected = VPK.inspect_directory(directory, cache)
            with patch.object(VPK, "iter_vpk_entries", side_effect=AssertionError("read unchanged VPK")):
                self.assertEqual(expected, VPK.inspect_directory(directory, cache))
            write_single_file_vpk(first, "missions/first.txt", mission("changed_m1", "changed_m2"))
            self.assertEqual(VPK.inspect_directory(directory, cache)["campaigns"][0]["first_map"], "changed_m1")
            second = directory / "second.vpk"
            write_single_file_vpk(second, "missions/second.txt", mission())
            self.assertEqual(len(VPK.inspect_directory(directory, cache)["campaigns"]), 2)
            first.unlink()
            self.assertEqual(len(VPK.inspect_directory(directory, cache)["campaigns"]), 1)
            before = cache.read_bytes()
            write_single_file_vpk(second, "missions/second.txt", mission(include_versus=False))
            with self.assertRaises(VPK.VpkError):
                VPK.inspect_directory(directory, cache)
            self.assertEqual(before, cache.read_bytes())

    def test_cached_campaigns_still_participate_in_conflict_checks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            cache = directory / "cache.json"
            write_single_file_vpk(directory / "first.vpk", "missions/first.txt", mission())
            VPK.inspect_directory(directory, cache)
            write_single_file_vpk(directory / "second.vpk", "missions/second.txt", mission())
            with self.assertRaisesRegex(VPK.VpkError, "declared more than once"):
                VPK.inspect_directory(directory, cache)

    def test_identical_vs_alias_prefers_base_mission(self) -> None:
        campaigns = [
            {
                "source": "campaign.vpk",
                "mission": "missions/example_vs.txt",
                "mission_id": "example_vs",
                "first_map": "example_m1",
                "maps": ["example_m1", "example_m2"],
                "name": "Example",
            },
            {
                "source": "campaign.vpk",
                "mission": "missions/example.txt",
                "mission_id": "example",
                "first_map": "example_m1",
                "maps": ["example_m1", "example_m2"],
                "name": "Example",
            },
        ]

        collapsed = VPK.collapse_versus_aliases(campaigns)

        self.assertEqual(len(collapsed), 1)
        self.assertEqual(collapsed[0]["mission_id"], "example")

    def test_inventory_reads_campaign_and_all_chapters(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_single_file_vpk(
                directory / "example.vpk", "missions/example.txt", mission()
            )
            inventory = VPK.inspect_directory(directory)

        campaign = inventory["campaigns"][0]
        self.assertEqual(campaign["mission_id"], "example")
        self.assertEqual(campaign["first_map"], "example_m1")
        self.assertEqual(campaign["maps"], ["example_m1", "example_m2"])
        self.assertEqual(campaign["name"], "Example Display")

    def test_inventory_rejects_campaign_without_versus_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_single_file_vpk(
                directory / "coop-only.vpk",
                "missions/coop-only.txt",
                mission(include_versus=False),
            )
            with self.assertRaisesRegex(
                VPK.VpkError,
                "missing versus mode required by AstMod/AstRedux",
            ):
                VPK.inspect_directory(directory)

    def test_inventory_accepts_separate_coop_and_versus_missions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_files_vpk(
                directory / "split.vpk",
                [
                    ("missions/example.txt", mission(include_versus=False), False),
                    ("missions/example_vs.txt", mission(), False),
                ],
            )
            inventory = VPK.inspect_directory(directory)

        self.assertEqual(len(inventory["campaigns"]), 1)
        self.assertEqual(inventory["campaigns"][0]["mission_id"], "example_vs")

    def test_numeric_suffix_without_dir_vpk_is_a_primary_vpk(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_single_file_vpk(
                directory / "campaign_362.vpk",
                "missions/campaign.txt",
                mission(),
            )
            inventory = VPK.inspect_directory(directory)

        self.assertEqual(inventory["files"], ["campaign_362.vpk"])
        self.assertEqual(inventory["campaigns"][0]["first_map"], "example_m1")

    def test_inventory_rejects_corrupt_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_single_file_vpk(
                directory / "broken.vpk",
                "missions/broken.txt",
                mission(),
                corrupt_crc=True,
            )
            with self.assertRaisesRegex(VPK.VpkError, "CRC mismatch"):
                VPK.inspect_directory(directory)

    def test_inventory_reports_all_invalid_vpks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_single_file_vpk(
                directory / "one.vpk",
                "missions/one.txt",
                mission(),
                corrupt_crc=True,
            )
            write_single_file_vpk(
                directory / "two.vpk",
                "missions/two.txt",
                mission(),
                corrupt_crc=True,
            )
            with self.assertRaises(VPK.VpkError) as context:
                VPK.inspect_directory(directory)

        self.assertIn("one.vpk", str(context.exception))
        self.assertIn("two.vpk", str(context.exception))

    def test_inventory_rejects_duplicate_map(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_single_file_vpk(
                directory / "broken.vpk",
                "missions/broken.txt",
                mission("duplicate_m1", "duplicate_m1"),
            )
            with self.assertRaisesRegex(VPK.VpkError, "declared more than once"):
                VPK.inspect_directory(directory)

    def test_inventory_rejects_duplicate_mission_id(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_single_file_vpk(
                directory / "one.vpk", "missions/shared.txt", mission("one_m1")
            )
            write_single_file_vpk(
                directory / "two.vpk", "missions/shared.txt", mission("two_m1")
            )
            with self.assertRaisesRegex(VPK.VpkError, "mission ID 'shared'"):
                VPK.inspect_directory(directory)

    def test_reconcile_preserves_official_curated_name_and_order(self) -> None:
        source = '''"MissionCycle"
{
    "官方战役"
    {
        "c1m1_hotel" { "name" "C1" }
    }
    "第三方战役"
    {
        "example_m1" { "name" "保留的名字" }
        "removed_m1" { "name" "应删除" }
    }
}
'''
        inventory = {
            "files": ["example.vpk", "new.vpk"],
            "campaigns": [
                {
                    "mission_id": "new",
                    "first_map": "new_m1",
                    "maps": ["new_m1"],
                    "name": "New",
                    "source": "new.vpk",
                },
                {
                    "mission_id": "example",
                    "first_map": "example_m1",
                    "maps": ["example_m1"],
                    "name": "Upstream Name",
                    "source": "example.vpk",
                },
            ],
        }
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source_path = directory / "missioncycle.txt"
            inventory_path = directory / "inventory.json"
            output_path = directory / "output.txt"
            source_path.write_text(source, encoding="utf-8")
            inventory_path.write_text(json.dumps(inventory), encoding="utf-8")
            VPK.reconcile_missioncycle(
                source_path, inventory_path, output_path, "第三方战役"
            )
            output = output_path.read_text(encoding="utf-8")

        self.assertIn('"c1m1_hotel"', output)
        self.assertIn('"example_m1"', output)
        self.assertIn('"保留的名字"', output)
        self.assertIn('"new_m1"', output)
        self.assertNotIn('"removed_m1"', output)
        self.assertLess(output.index('"example_m1"'), output.index('"new_m1"'))


if __name__ == "__main__":
    unittest.main()
