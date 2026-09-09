#!/usr/bin/env python3
"""Interval Linux diagnostics. Thread CPU: one CPU=100%; host CPU: all CPUs=100%.

Missing counters are null/absent. Uses only the server's Python standard library.
"""
import argparse
from collections import deque
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import time


def read(path):
    try:
        return Path(path).read_text()
    except OSError:
        return ""


def pairs(path):
    result = {}
    for line in read(path).splitlines():
        parts = line.replace(":", "").split()
        if len(parts) >= 2:
            try:
                result[parts[0]] = int(parts[1])
            except ValueError:
                pass
    return result


def delta(current, previous):
    return {k: v - previous[k] for k, v in current.items()
            if k in previous and v >= previous[k]}


def pressure(path):
    result = {}
    for line in read(path).splitlines():
        parts = line.split()
        result[parts[0]] = {k: float(v) for k, v in
                            (field.split("=") for field in parts[1:])}
    return result


def proc_stat(path):
    value = read(path)
    if not value:
        return None
    # comm may contain spaces and parentheses. Index zero below is field 3.
    fields = value[value.rfind(")") + 2:].split()
    return dict(start=int(fields[19]), ticks=int(fields[11]) + int(fields[12]),
                majflt=int(fields[9]), rss_kb=int(fields[21]) * os.sysconf("SC_PAGE_SIZE") // 1024,
                state=fields[0], cpu=int(fields[36]))


class Collector:
    def __init__(self, service):
        self.service = service
        self.previous = None
        self.pid = None
        self.hz = os.sysconf("SC_CLK_TCK")

    def find_process(self):
        if self.pid and read(f"/proc/{self.pid}/comm").strip() == "srcds_linux":
            return self.pid
        # Observe only the configured service, not other srcds instances.
        for value in read(f"/sys/fs/cgroup/system.slice/{self.service}/cgroup.procs").split():
            if read(f"/proc/{value}/comm").strip() == "srcds_linux":
                self.pid = int(value)
                return self.pid
        self.pid = None
        return None

    def raw(self):
        now = time.monotonic()
        cpus = {}
        for line in read("/proc/stat").splitlines():
            a = line.split()
            if a[0].startswith("cpu"):
                cpus[a[0]] = list(map(int, a[1:9]))  # guest already included in user/nice
        cg = Path("/sys/fs/cgroup/system.slice") / self.service
        pid = self.find_process()
        threads = {}
        if pid:
            for folder in Path(f"/proc/{pid}/task").glob("*"):
                stat = proc_stat(folder / "stat")
                if stat:
                    stat["sched"] = [int(x) for x in read(folder / "schedstat").split()]
                    stat["switches"] = {k: v for k, v in pairs(folder / "status").items()
                                        if k.endswith("ctxt_switches")}
                    threads[folder.name] = stat
        disks = {}
        for line in read("/proc/diskstats").splitlines():
            a = line.split()
            if (Path("/sys/block") / a[2]).exists() and not a[2].startswith(("loop", "ram")):
                disks[a[2]] = list(map(int, a[3:]))
        network = {}
        for line in read("/proc/net/dev").splitlines()[2:]:
            name, values = line.split(":", 1)
            network[name.strip()] = list(map(int, values.split()))
        return dict(mono=now, ts=datetime.now().astimezone().isoformat(), cpus=cpus,
                    mem=pairs("/proc/meminfo"), pid=pid, process=proc_stat(f"/proc/{pid}/stat") if pid else None,
                    threads=threads, disks=disks, network=network,
                    vm=pairs("/proc/vmstat"), cg=pairs(cg / "cpu.stat"),
                    cpu_max=read(cg / "cpu.max").strip() or None,
                    schedstats=read("/proc/sys/kernel/sched_schedstats").strip() == "1",
                    psi={name: pressure(f"/proc/pressure/{name}") for name in ("cpu", "io", "memory")},
                    memory_events=pairs(cg / "memory.events"), io=pairs(f"/proc/{pid}/io") if pid else {})

    def sample(self):
        r = self.raw()
        p = self.previous
        self.previous = r
        if p is None:
            return None
        seconds = r["mono"] - p["mono"]
        out = dict(schema=1, ts=r["ts"], interval_s=round(seconds, 4), pid=r["pid"],
                   load=read("/proc/loadavg").split()[:3], cpu={}, threads={},
                   memory_kb={k: r["mem"].get(k) for k in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree")},
                   psi=r["psi"], schedstats_enabled=r["schedstats"],
                   cgroup_cpu_max=r["cpu_max"], cgroup_cpu_delta=delta(r["cg"], p["cg"]),
                   memory_events=r["memory_events"], disks={}, network={})
        out["memory_kb"]["SwapUsed"] = r["mem"].get("SwapTotal", 0) - r["mem"].get("SwapFree", 0)
        out["vm_delta"] = {k: v for k, v in delta(r["vm"], p["vm"]).items()
                           if k in ("pswpin", "pswpout", "pgmajfault", "oom_kill")}
        for name, values in r["cpus"].items():
            if name not in p["cpus"]:
                continue
            d = [a - b for a, b in zip(values, p["cpus"][name])]
            total = sum(d)
            if total > 0 and min(d) >= 0:
                out["cpu"][name] = {k: round(100 * v / total, 3) for k, v in
                    zip(("user", "nice", "system", "idle", "iowait", "irq", "softirq", "steal"), d)}
        same_process = r["pid"] == p["pid"] and r["process"] and p["process"] and r["process"]["start"] == p["process"]["start"]
        out["process_changed"] = bool(p["pid"] and not same_process)
        if same_process:
            out["process"] = dict(rss_kb=r["process"]["rss_kb"],
                cpu_pct=round((r["process"]["ticks"] - p["process"]["ticks"]) / self.hz / seconds * 100, 3),
                io_delta=delta(r["io"], p["io"]))
            for tid, cur in r["threads"].items():
                prev = p["threads"].get(tid)
                if prev is None or prev["start"] != cur["start"]:
                    continue
                sd = [a - b for a, b in zip(cur["sched"], prev["sched"])]
                out["threads"][tid] = dict(cpu_pct=round((cur["ticks"] - prev["ticks"]) / self.hz / seconds * 100, 3),
                    state=cur["state"], last_cpu=cur["cpu"], run_ms=round(sd[0] / 1e6, 3) if sd else None,
                    wait_ms=round(sd[1] / 1e6, 3) if len(sd) > 1 and r["schedstats"] and p["schedstats"] else None,
                    switches_delta=delta(cur["switches"], prev["switches"]), major_faults=cur["majflt"] - prev["majflt"])
        for name, cur in r["disks"].items():
            if name not in p["disks"]:
                continue
            d = [a - b for a, b in zip(cur, p["disks"][name])]
            if any(d[i] < 0 for i in (0, 2, 3, 4, 6, 7, 9, 10)):
                continue  # Device counters reset; not a valid interval.
            out["disks"][name] = dict(read_kb_s=round(d[2] / 2 / seconds, 3), write_kb_s=round(d[6] / 2 / seconds, 3),
                read_await_ms=round(d[3] / d[0], 3) if d[0] else None,
                write_await_ms=round(d[7] / d[4], 3) if d[4] else None,
                util_pct=round(d[9] / (seconds * 10), 3), queue_avg=round(d[10] / (seconds * 1000), 3))
        for name, cur in r["network"].items():
            if name in p["network"]:
                d = [a - b for a, b in zip(cur, p["network"][name])]
                if min(d) < 0:
                    continue
                out["network"][name] = dict(rx_bytes=d[0], rx_packets=d[1], rx_errors=d[2], rx_drops=d[3],
                                            tx_bytes=d[8], tx_packets=d[9], tx_errors=d[10], tx_drops=d[11])
        return out


def prune(directory, pattern, days):
    cutoff = time.time() - days * 86400
    for path in directory.glob(pattern):
        if path.is_file() and path.stat().st_mtime < cutoff:
            path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=0, help="bounded stdout-only check; do not persist")
    options = parser.parse_args()
    interval = max(1, float(os.environ.get("OBSERVE_INTERVAL_SECONDS", 5)))
    retention = max(1, int(os.environ.get("OBSERVE_RETENTION_DAYS", 7)))
    service = os.environ.get("SERVICE_NAME", "l4d2.service")
    collector = Collector(service)
    state = Path("/var/lib/l4d2-observe")
    recent = deque(maxlen=max(1, int(120 / interval)))
    if not options.samples:
        os.umask(0o027)
        (state / "incidents").mkdir(parents=True, exist_ok=True)
    collector.sample()
    count = 0
    last_cleanup = 0
    last_incident = 0
    high_steal = 0
    deadline = time.monotonic() + interval
    while True:
        time.sleep(max(0, deadline - time.monotonic()))
        start = time.monotonic()
        sample = collector.sample()
        sample["collection_ms"] = round((time.monotonic() - start) * 1000, 3)
        line = json.dumps(sample, separators=(",", ":"))
        if options.samples:
            print(line, flush=True)
            count += 1
            if count >= options.samples:
                break
        else:
            # Retain normal and slow windows equally, without size truncation.
            with (state / f"host-{sample['ts'][:10]}.jsonl").open("a") as stream:
                stream.write(line + "\n")
            recent.append(line)
            steal = max((cpu["steal"] for name, cpu in sample["cpu"].items() if name != "cpu"), default=0)
            high_steal = high_steal + 1 if steal >= 10 else 0
            wait = sample["threads"].get(str(sample["pid"]), {}).get("wait_ms") or 0
            reason = ("process-change" if sample["process_changed"] else "cpu-steal" if high_steal >= 3 else
                      "scheduler-wait" if wait >= sample["interval_s"] * 100 else
                      "cgroup-throttle" if sample["cgroup_cpu_delta"].get("nr_throttled", 0) else None)
            if reason and (sample["process_changed"] or start - last_incident >= 300):
                stamp = datetime.now().astimezone().strftime("%Y%m%dT%H%M%S%z")
                base = state / "incidents" / f"{stamp}-{reason}"
                base.with_suffix(".jsonl").write_text("\n".join(recent) + "\n")
                try:
                    result = subprocess.run(["journalctl", "-u", service, "-n", "200", "--no-pager"],
                                            capture_output=True, text=True, timeout=3)
                    base.with_suffix(".log").write_text(result.stdout)
                except subprocess.TimeoutExpired:
                    pass
                last_incident = start
            if start - last_cleanup >= 3600:
                prune(state, "host-????-??-??.jsonl", retention)
                prune(state / "incidents", "*.jsonl", retention)
                prune(state / "incidents", "*.log", retention)
                last_cleanup = start
        deadline += interval
        if deadline < time.monotonic():
            deadline = time.monotonic() + interval


if __name__ == "__main__":
    main()
