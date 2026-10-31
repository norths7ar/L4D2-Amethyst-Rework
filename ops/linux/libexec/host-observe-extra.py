#!/usr/bin/env python3
"""Low-frequency process summaries and IPv4 ICMP probes; Linux stdlib only."""

import argparse
from datetime import datetime
import ipaddress
import json
import os
from pathlib import Path
import select
import socket
import struct
import time


def timestamp():
    return datetime.now().astimezone().isoformat()


class Processes:
    def __init__(self):
        self.previous = {}
        self.last = None
        self.hz = os.sysconf("SC_CLK_TCK")

    def sample(self):
        begin = time.monotonic()
        current = {}
        skipped = 0
        for folder in Path("/proc").iterdir():
            if not folder.name.isdecimal():
                continue
            try:
                raw = (folder / "stat").read_text()
                end = raw.rfind(")")
                fields = raw[end + 2:].split()
                io = dict(line.split(": ", 1) for line in (folder / "io").read_text().splitlines())
                current[(int(folder.name), int(fields[19]))] = {
                    "name": raw[raw.find("(") + 1:end],
                    "ticks": int(fields[11]) + int(fields[12]),
                    "read_bytes": int(io["read_bytes"]),
                    "write_bytes": int(io["write_bytes"]),
                }
            except (OSError, ValueError, KeyError, IndexError):
                skipped += 1  # Process exit or inaccessible counters, not zero activity.
        interval = begin - self.last if self.last is not None else None
        deltas = []
        for key, value in current.items():
            old = self.previous.get(key)
            if old is None or interval is None:
                continue
            deltas.append({
                "pid": key[0], "start_ticks": key[1], "name": value["name"],
                "cpu_pct": round((value["ticks"] - old["ticks"]) / self.hz / interval * 100, 3),
                "read_bytes": max(0, value["read_bytes"] - old["read_bytes"]),
                "write_bytes": max(0, value["write_bytes"] - old["write_bytes"]),
            })
        self.previous, self.last = current, begin
        return {
            "kind": "processes", "ts": timestamp(),
            "interval_s": round(interval, 3) if interval is not None else None,
            "baseline": interval is None, "processes_read": len(current), "skipped": skipped,
            "new_processes": len(current) - len(deltas),
            "top_cpu": sorted(deltas, key=lambda p: p["cpu_pct"], reverse=True)[:5],
            "top_io": sorted(deltas, key=lambda p: p["read_bytes"] + p["write_bytes"], reverse=True)[:5],
            "collection_ms": round((time.monotonic() - begin) * 1000, 3),
        }


def checksum(data):
    if len(data) % 2:
        data += b"\0"
    value = sum(struct.unpack(f"!{len(data) // 2}H", data))
    value = (value & 0xFFFF) + (value >> 16)
    value = (value & 0xFFFF) + (value >> 16)
    return ~value & 0xFFFF


def probe(targets):
    """One request per target; all responses share a one-second deadline."""
    begin = time.monotonic()
    results = []
    pending = {}
    nonce = os.urandom(16)
    ident = os.getpid() & 0xFFFF
    for sequence, target in enumerate(targets):
        result = dict(target, status="timeout", rtt_ms=None)
        results.append(result)
        sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
            sock.setblocking(False)
            header = struct.pack("!BBHHH", 8, 0, 0, ident, sequence)
            packet = struct.pack("!BBHHH", 8, 0, checksum(header + nonce), ident, sequence) + nonce
            sent = time.monotonic()
            sock.sendto(packet, (target["address"], 0))
            pending[sock] = (result, sent, sequence)
        except OSError as exc:
            result.update(status="error", error=str(exc))
            if sock is not None:
                sock.close()
    deadline = time.monotonic() + 1
    try:
        while pending and time.monotonic() < deadline:
            ready, _, _ = select.select(list(pending), [], [], max(0, deadline - time.monotonic()))
            for sock in ready:
                result, sent, sequence = pending[sock]
                try:
                    packet, source = sock.recvfrom(2048)
                except BlockingIOError:
                    continue
                except OSError as exc:
                    result.update(status="error", error=str(exc))
                    sock.close()
                    del pending[sock]
                    continue
                offset = (packet[0] & 15) * 4 if packet else 0
                icmp = packet[offset:]
                if len(icmp) < 24 or source[0] != result["address"]:
                    continue
                kind, code, _, reply_id, reply_sequence = struct.unpack("!BBHHH", icmp[:8])
                if (kind, code, reply_id, reply_sequence, icmp[8:24]) != (0, 0, ident, sequence, nonce):
                    continue
                result.update(status="ok", rtt_ms=round((time.monotonic() - sent) * 1000, 3))
                sock.close()
                del pending[sock]
    finally:
        for sock in pending:
            sock.close()
    return {"kind": "network", "ts": timestamp(), "protocol": "icmp_echo_ipv4",
            "timeout_s": 1, "targets": results,
            "collection_ms": round((time.monotonic() - begin) * 1000, 3)}


class Log:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o750)
        self.path = None
        self.last_cleanup = 0

    def append(self, record):
        day = record["ts"][:10]
        rotate = self.path is None or day not in self.path.name or self.path.stat().st_size >= 8 * 1024**2
        if rotate:
            self.path = self.directory / f"extra-{day}-{time.time_ns()}.jsonl"
        with self.path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(record, separators=(",", ":")) + "\n")
        if rotate or time.monotonic() - self.last_cleanup >= 3600:
            files = sorted(self.directory.glob("extra-*.jsonl"), key=lambda p: p.stat().st_mtime)
            total = sum(p.stat().st_size for p in files)
            for path in files:
                stat = path.stat()
                if path != self.path and (stat.st_mtime < time.time() - 7 * 86400 or total > 128 * 1024**2):
                    path.unlink()
                    total -= stat.st_size
            self.last_cleanup = time.monotonic()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="/etc/l4d2-observe-extra.json")
    parser.add_argument("--samples", type=int, default=0, help="process samples to stdout, without log writes")
    options = parser.parse_args()
    config = json.loads(Path(options.config).read_text())
    targets = config.get("targets", [])
    if len(targets) > 4:
        parser.error("at most four probe targets are supported")
    for target in targets:
        ipaddress.IPv4Address(target["address"])
        if not target.get("name") or not target.get("role"):
            parser.error("targets need name, role, and numeric IPv4 address")
    os.umask(0o027)
    log = None if options.samples else Log("/var/lib/l4d2-observe-extra")
    processes = Processes()
    next_process = next_network = time.monotonic()
    count = 0
    while True:
        now = time.monotonic()
        records = []
        if now >= next_process:
            records.append(processes.sample())
            next_process = time.monotonic() + 15
            count += 1
        if now >= next_network:
            records.append(probe(targets))
            next_network = now + 10
        for record in records:
            if log:
                log.append(record)
            else:
                print(json.dumps(record), flush=True)
        if options.samples and count >= options.samples:
            break
        time.sleep(max(0, min(next_process, next_network) - time.monotonic()))


if __name__ == "__main__":
    main()
