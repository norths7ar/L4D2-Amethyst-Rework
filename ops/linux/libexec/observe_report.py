#!/usr/bin/env python3
"""Read daily host/game observations and print a Markdown comparison, without diagnosis."""
import argparse
from collections import defaultdict
from datetime import date, datetime, timezone
import json
import math
from pathlib import Path
import shlex


def number(value):
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (TypeError, ValueError):
        return None


def fmt(value):
    return "未知" if value is None else f"{value:.2f}"


def cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ").replace("\r", " ")


def span(values):
    values = [v for v in values if v is not None]
    return f"{fmt(min(values))}–{fmt(max(values))}" if values else "未知"


def read_records(path, game, warnings):
    records = []
    try:
        stream = path.open(encoding="utf-8")
    except OSError as error:
        warnings.append(f"{path.name}: {error}")
        return records
    bad = 0
    with stream:
        for line in stream:
            if not line.strip():
                continue
            try:
                if game:
                    row = dict(token.split("=", 1) for token in shlex.split(line))
                    timestamp = number(row.get("ts"))
                    if timestamp is None:
                        raise ValueError("missing timestamp")
                else:
                    row = json.loads(line)
                    if not isinstance(row, dict):
                        raise ValueError("host record must be an object")
                    parsed = datetime.fromisoformat(row["ts"])
                    if parsed.tzinfo is None:
                        raise ValueError("host timestamp must include timezone")
                    timestamp = parsed.timestamp()
                row["_time"] = timestamp
                records.append(row)
            except (ValueError, TypeError, KeyError):
                bad += 1
    if bad:
        warnings.append(f"{path.name}: 跳过 {bad} 行无效记录")
    return sorted(records, key=lambda row: row["_time"])


def active(row):
    humans = number(row.get("humans"))
    return (row.get("event") == "sample" and humans is not None and humans > 0
            and number(row.get("processing")) == 1
            and number(row.get("paused")) != 1
            and number(row.get("hibernating")) != 1)


def unknown_state(row):
    return any(number(row.get(key)) not in (0, 1)
               for key in ("paused", "hibernating", "ready"))


def windows(rows):
    merged = []
    for row in rows:
        duration = number(row.get("window_s"))
        if duration is None or duration <= 0:
            continue
        start, end = row["_time"] - duration, row["_time"]
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    return merged


def host_matches(host, periods):
    matches = []
    for row in host:
        duration = number(row.get("interval_s"))
        if duration is None or duration <= 0:
            continue
        end = row["_time"]
        overlap = sum(max(0, min(end, b) - max(end - duration, a)) for a, b in periods)
        if overlap > 0:
            matches.append((row, overlap))
    return matches


def host_value(row, key):
    if key in ("cpu_pct", "wait_pct"):
        thread = row.get("threads", {}).get(str(row.get("pid")), {})
        if key == "cpu_pct":
            return number(thread.get(key))
        wait = number(thread.get("wait_ms"))
        interval = number(row.get("interval_s"))
        return wait / (interval * 10) if wait is not None and interval and row.get("schedstats_enabled") else None
    if key == "steal":
        return number(row.get("cpu", {}).get("cpu", {}).get("steal"))
    if key == "throttle_ms":
        value = number(row.get("cgroup_cpu_delta", {}).get("throttled_usec"))
        return value / 1000 if value is not None else None
    if key == "rss":
        value = number(row.get("process", {}).get("rss_kb"))
    else:
        value = number(row.get("memory_kb", {}).get("MemAvailable"))
    return value / 1024 if value is not None else None


def weighted_host(matches, key):
    values = [(host_value(row, key), weight) for row, weight in matches]
    values = [(value, weight) for value, weight in values if value is not None]
    if not values:
        return "未知"
    mean = sum(value * weight for value, weight in values) / sum(weight for _, weight in values)
    return f"{fmt(mean)} / {fmt(max(value for value, _ in values))} ({len(values)})"


def frames(rows):
    usable = [(row, number(row.get("frame_intervals"))) for row in rows]
    usable = [(row, count) for row, count in usable if count is not None and count > 0]
    averages = [(number(row.get("frame_interval_avg_ms")), count) for row, count in usable]
    averages = [(value, count) for value, count in averages if value is not None]
    avg = sum(value * count for value, count in averages) / sum(count for _, count in averages) if averages else None
    maximums = [number(row.get("frame_interval_max_ms")) for row, _ in usable]
    maximums = [value for value in maximums if value is not None]
    thresholds = []
    for key in ("over20", "over50", "over100"):
        values = [(number(row.get(key)), count) for row, count in usable]
        values = [(value, count) for value, count in values if value is not None]
        thresholds.append(f"{sum(value for value, _ in values):.0f} ({100 * sum(value for value, _ in values) / sum(count for _, count in values):.2f}%, n={len(values)})" if values else "未知")
    return f"{fmt(avg)} / {fmt(max(maximums) if maximums else None)}", " / ".join(thresholds)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", required=True, type=date.fromisoformat)
    parser.add_argument("--host-dir", type=Path, default=Path("/var/lib/l4d2-observe"))
    parser.add_argument("--game-dir", type=Path, default=Path("/home/l4d2/server/left4dead2/addons/sourcemod/logs"))
    options = parser.parse_args()
    warnings = []
    host = read_records(options.host_dir / f"host-{options.date.isoformat()}.jsonl", False, warnings)
    game = read_records(options.game_dir / f"server_observe_{options.date:%Y%m%d}.log", True, warnings)
    tz = datetime.fromisoformat(host[0]["ts"]).tzinfo if host else timezone.utc

    def clock(timestamp):
        return datetime.fromtimestamp(timestamp, tz).strftime("%H:%M:%S%z")

    print(f"# 服务器观测报告 {options.date}\n")
    print(f"主机记录 {len(host)} 条；游戏记录 {len(game)} 条。时间显示带 UTC 偏移（无主机记录时使用 UTC）。仅读取指定日期文件，不补读相邻日期。\n")
    print("帧数据是墙钟帧间隔，不是插件 CPU 耗时。仅汇总 humans>0、processing=1、paused!=1、hibernating!=1 的 sample；未知暂停/休眠状态仍纳入并单列。工作量是窗口末快照，不能代表窗口内峰值。同名地图多次游玩合并。缺失不是零，不推断根因。\n")
    for warning in warnings:
        print(f"- {cell(warning)}")
    maps = defaultdict(list)
    for row in game:
        if row.get("event") == "sample":
            maps[row.get("map", "未知地图")].append(row)
    print("\n## 活跃地图窗口\n")
    if not maps:
        print("没有游戏 sample 记录，无法汇总地图窗口。\n")
    for name, all_rows in maps.items():
        rows = [row for row in all_rows if active(row)]
        print(f"### {cell(name)}\n")
        print(f"纳入 {len(rows)}/{len(all_rows)} 个样本；其中暂停/休眠/ready 状态有未知值 {sum(unknown_state(row) for row in rows)} 个。\n")
        if not rows:
            continue
        periods = windows(rows)
        matches = host_matches(host, periods)
        frame, thresholds = frames(rows)
        print(f"时间：{clock(rows[0]['_time'] - (number(rows[0].get('window_s')) or 0))}–{clock(rows[-1]['_time'])}；有效窗口合计 {sum(b-a for a,b in periods):.1f}s；重叠主机样本 {len(matches)}，重叠时长 {sum(weight for _, weight in matches):.1f}s。\n")
        print(f"帧间隔加权均值 / 最大值：{frame} ms；>20 / >50 / >100 ms：{thresholds}。\n")
        print("工作量范围：" + "；".join(f"{label} {span(number(row.get(key)) for row in rows)}" for label, key in (("小怪", "common_alive"), ("特感", "special_alive"), ("非玩家实体", "nonclient_entities"))) + "。\n")
        print("| 指标 | 均值 / 最大值（有效主机样本数） |\n|---|---|")
        for label, key in (("主线程 CPU %（单核=100%）", "cpu_pct"), ("主线程调度等待占窗口 %", "wait_pct"), ("整机 steal %", "steal")):
            print(f"| {label} | {weighted_host(matches, key)} |")
        print(f"\n主机窗口内 throttle 增量范围（ms/原采样窗口，非地图累计）：{span(host_value(row, 'throttle_ms') for row, _ in matches)}；进程 RSS MiB：{span(host_value(row, 'rss') for row, _ in matches)}；可用内存 MiB：{span(host_value(row, 'available') for row, _ in matches)}。\n")
    print("\n主机均值按与游戏有效窗口的重叠秒数加权；边界处主机区间指标仍覆盖完整原采样窗口。\n\n## 手工标记前后 15 秒\n")
    marks = [row for row in game if row.get("event") == "mark"]
    if not marks:
        print("没有标记记录。")
    for mark in marks:
        stamp = mark["_time"]
        print(f"### {clock(stamp)} {cell(mark.get('map', ''))} — {cell(mark.get('label', ''))}\n")
        print("| 时间 | 记录 | 对照 |\n|---|---|---|")
        nearby = [(row, True) for row in game if row.get("event") == "sample" and abs(row["_time"] - stamp) <= 15]
        nearby += [(row, False) for row in host if abs(row["_time"] - stamp) <= 15]
        for row, is_game in sorted(nearby, key=lambda item: item[0]["_time"]):
            if is_game:
                frame, thresholds = frames([row])
                detail = f"{cell(row.get('map', ''))}；{'纳入' if active(row) else '排除'}；avg/max {frame} ms；>20/50/100 {thresholds}；" + "; ".join(f"{key}={cell(row.get(key, '未知'))}" for key in ("humans", "processing", "paused", "hibernating", "common_alive", "special_alive", "nonclient_entities"))
            else:
                detail = "；".join(f"{label} {fmt(host_value(row, key))}" for label, key in (("主线程CPU%", "cpu_pct"), ("等待%", "wait_pct"), ("steal%", "steal"), ("throttle ms", "throttle_ms"), ("RSS MiB", "rss")))
            print(f"| {clock(row['_time'])} | {'游戏' if is_game else '主机'} | {detail} |")
        if not nearby:
            print("| — | — | 无附近样本 |")
        print()


if __name__ == "__main__":
    main()
