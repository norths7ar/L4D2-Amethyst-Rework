from __future__ import annotations

import importlib.util
import json
import struct
import sys
import tempfile
import unittest
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
