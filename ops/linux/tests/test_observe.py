"""Deterministic procfs fixtures; no Linux host or third-party packages required."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "observe", Path(__file__).parents[1] / "libexec" / "observe.py"
)
OBSERVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OBSERVE)


def snapshot(seconds=0, pid=100):
    process = dict(start=10, ticks=100 + seconds * 100, rss_kb=1024,
                   majflt=0, state="R", cpu=0)
    thread = dict(process, sched=[seconds * 1_000_000_000,
                                 seconds * 10_000_000, seconds * 100],
                  switches={"voluntary_ctxt_switches": seconds * 100})
    return dict(mono=100.0 + seconds, ts="2026-09-09T23:00:00+08:00",
                cpus={"cpu": [100] * 8, "cpu0": [50] * 8, "cpu1": [50] * 8},
                mem={"MemTotal": 4096, "MemAvailable": 2048,
                     "SwapTotal": 1024, "SwapFree": 1000},
                pid=pid, process=process, threads={str(pid): thread}, disks={},
                network={}, vm={}, cg={}, cpu_max="max 100000", schedstats=True,
                psi={"cpu": {}, "io": {}, "memory": {}}, memory_events={}, io={})


class CollectorTests(unittest.TestCase):
    def setUp(self):
        # Windows has no sysconf; fixtures use the Linux 100 Hz accounting scale.
        with patch.object(OBSERVE.os, "sysconf", return_value=100, create=True):
            self.collector = OBSERVE.Collector("l4d2.service")

    def collect_pair(self, previous, current):
        with patch.object(self.collector, "raw", side_effect=[previous, current]), \
                patch.object(OBSERVE, "read", return_value="0.0 0.0 0.0 1/10 100"):
            self.assertIsNone(self.collector.sample())
            return self.collector.sample()

    def test_first_sample_has_no_invented_interval(self):
        with patch.object(self.collector, "raw", return_value=snapshot()):
            self.assertIsNone(self.collector.sample())

    def test_per_cpu_steal_and_thread_time_units(self):
        previous, current = snapshot(), snapshot(5)
        increments = {"cpu0": [40, 0, 10, 30, 0, 0, 0, 20],
                      "cpu1": [90, 0, 10, 0, 0, 0, 0, 0],
                      "cpu": [130, 0, 20, 30, 0, 0, 0, 20]}
        for name, values in increments.items():
            current["cpus"][name] = [a + b for a, b in zip(previous["cpus"][name], values)]
        sample = self.collect_pair(previous, current)
        self.assertEqual(sample["cpu"]["cpu0"]["steal"], 20.0)
        self.assertEqual(sample["cpu"]["cpu1"]["steal"], 0.0)
        self.assertEqual(sample["cpu"]["cpu"]["steal"], 10.0)
        self.assertEqual(sample["threads"]["100"]["cpu_pct"], 100.0)
        self.assertEqual(sample["threads"]["100"]["run_ms"], 5000.0)
        self.assertEqual(sample["threads"]["100"]["wait_ms"], 50.0)
        self.assertEqual(sample["memory_kb"]["SwapUsed"], 24)

    def test_process_replacement_does_not_join_thread_counters(self):
        for new_pid in (100, 200):
            with self.subTest(new_pid=new_pid):
                previous, current = snapshot(), snapshot(5, pid=new_pid)
                current["process"]["start"] = 200
                sample = self.collect_pair(previous, current)
                self.assertTrue(sample["process_changed"])
                self.assertEqual(sample["threads"], {})
                self.assertNotIn("process", sample)
                self.collector.previous = None

    def test_unavailable_scheduler_wait_is_null_not_zero(self):
        for enabled, scheduler_values in ((False, [0, 0, 0]), (True, [])):
            with self.subTest(enabled=enabled, scheduler_values=scheduler_values):
                previous, current = snapshot(), snapshot(5)
                previous["schedstats"] = current["schedstats"] = enabled
                current["threads"]["100"]["sched"] = scheduler_values
                sample = self.collect_pair(previous, current)
                self.assertIsNone(sample["threads"]["100"]["wait_ms"])
                if not scheduler_values:
                    self.assertIsNone(sample["threads"]["100"]["run_ms"])
                self.collector.previous = None

    def test_thread_exit_during_procfs_collection(self):
        # The directory was enumerated, but stat or its subsequent files vanish.
        for stat_disappears in (True, False):
            with self.subTest(stat_disappears=stat_disappears):
                process = snapshot()["process"]

                def read_stat(path):
                    if "task" in Path(path).parts and stat_disappears:
                        return None
                    return copy.deepcopy(process)

                with patch.object(self.collector, "find_process", return_value=100), \
                        patch.object(OBSERVE.Path, "glob", return_value=[Path("/proc/100/task/100")]), \
                        patch.object(OBSERVE, "read", return_value=""), \
                        patch.object(OBSERVE, "proc_stat", side_effect=read_stat):
                    raw = self.collector.raw()
                if stat_disappears:
                    self.assertEqual(raw["threads"], {})
                else:
                    self.assertEqual(raw["threads"]["100"]["sched"], [])
                    self.assertEqual(raw["threads"]["100"]["switches"], {})


if __name__ == "__main__":
    unittest.main()
