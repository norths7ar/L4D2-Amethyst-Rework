from __future__ import annotations

import importlib.util
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "libexec" / "vpk_campaigns.py"
SPEC = importlib.util.spec_from_file_location("vpk_campaigns", MODULE_PATH)
assert SPEC and SPEC.loader
VPK = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VPK
SPEC.loader.exec_module(VPK)


def write_single_file_vpk(path: Path, internal_path: str, payload: bytes) -> None:
    directory, leaf = internal_path.rsplit("/", 1)
    filename, extension = leaf.rsplit(".", 1)
    tree = bytearray()
    tree.extend(extension.encode() + b"\0")
    tree.extend(directory.encode() + b"\0")
    tree.extend(filename.encode() + b"\0")
    tree.extend(struct.pack("<IHHIIH", 0, 0, 0x7FFF, 0, len(payload), 0xFFFF))
    tree.extend(b"\0\0\0")
    header = struct.pack("<III", 0x55AA1234, 1, len(tree))
    path.write_bytes(header + tree + payload)


class VpkCampaignTests(unittest.TestCase):
    def test_inventory_reads_campaign_mission(self) -> None:
        mission = b'''"mission"
{
    "Name" "Example Campaign"
    "DisplayTitle" "Example Display"
    "modes"
    {
        "coop"
        {
            "1" { "Map" "example_m1" }
            "2" { "Map" "example_m2" }
        }
    }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_single_file_vpk(directory / "example.vpk", "missions/example.txt", mission)
            inventory = VPK.inspect_directory(directory)

        self.assertEqual(inventory["files"], ["example.vpk"])
        self.assertEqual(inventory["campaigns"][0]["first_map"], "example_m1")
        self.assertEqual(inventory["campaigns"][0]["maps"], ["example_m1", "example_m2"])
        self.assertEqual(inventory["campaigns"][0]["name"], "Example Display")

    def test_inventory_rejects_duplicate_map_within_one_vpk(self) -> None:
        mission = b'''"mission"
{
    "Name" "Broken Campaign"
    "modes"
    {
        "coop"
        {
            "1" { "Map" "duplicate_m1" }
            "2" { "Map" "duplicate_m1" }
        }
    }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            write_single_file_vpk(directory / "broken.vpk", "missions/broken.txt", mission)
            with self.assertRaisesRegex(VPK.VpkError, "declared more than once"):
                VPK.inspect_directory(directory)

    def test_reconcile_preserves_official_and_curated_name(self) -> None:
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
                {"first_map": "new_m1", "maps": ["new_m1"], "name": "New", "source": "new.vpk"},
                {
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
            VPK.reconcile_missioncycle(source_path, inventory_path, output_path, "第三方战役")
            output = output_path.read_text(encoding="utf-8")

        self.assertIn('"c1m1_hotel"', output)
        self.assertIn('"example_m1"', output)
        self.assertIn('"保留的名字"', output)
        self.assertIn('"new_m1"', output)
        self.assertNotIn('"removed_m1"', output)
        self.assertLess(output.index('"example_m1"'), output.index('"new_m1"'))


if __name__ == "__main__":
    unittest.main()
