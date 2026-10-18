#!/usr/bin/env python3
"""Summarize recorded measurements; never runs tests or enables a candidate."""

import argparse
from collections import defaultdict
import json
from pathlib import Path
import statistics
import sys


MARKER = "PERF_CANDIDATE_JSON "
EXPERIMENTS = ("media-date-section-cache", "quick-clean-selection-index")
SCENARIOS = ("cold-build", "warm-query", "interactions-total")
SIZES = (1_000, 10_000, 100_000)
SAMPLES = set(range(5))
NAMES = {
    "media-date-section-cache": "日期分组缓存",
    "quick-clean-selection-index": "快速清理汇总索引",
}
SCENARIO_NAMES = {
    "cold-build": "首次准备＋查询",
    "warm-query": "准备完成后的查询",
    "interactions-total": "首次准备＋全部交互",
}


def measurements(path):
    groups = defaultdict(dict)
    errors = []
    with path.open(encoding="utf-8", errors="replace") as source:
        for line_number, line in enumerate(source, 1):
            if MARKER not in line:
                continue
            try:
                record, _ = json.JSONDecoder().raw_decode(line.split(MARKER, 1)[1].lstrip())
                experiment, scenario = record["experiment"], record["scenario"]
                size, sample = record["asset_count"], record["sample"]
                if experiment not in EXPERIMENTS or scenario not in SCENARIOS or size not in SIZES:
                    raise ValueError("unknown experiment, scenario, or fixture size")
                if type(sample) is not int or sample not in SAMPLES:
                    raise ValueError("sample must be an integer from zero through four")
                for field in ("baseline_ns", "candidate_ns"):
                    if type(record[field]) is not int or record[field] <= 0:
                        raise ValueError("durations must be positive integer nanoseconds")
                if type(record["equivalent"]) is not bool:
                    raise ValueError("equivalent must be a boolean")
                key = (experiment, size, scenario)
                if sample in groups[key]:
                    raise ValueError("duplicate sample; use the output from a single test run")
                groups[key][sample] = record
            except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
                # Do not echo input lines, which may contain unrelated CI data.
                errors.append(f"第 {line_number} 行测量数据无效（{error}）。")
    return groups, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, help="Full unit-test output from one authorized run")
    args = parser.parse_args()
    try:
        groups, errors = measurements(args.log)
    except OSError as error:
        parser.error(str(error))

    print("# 新旧性能对比：该不该替换？\n")
    print("**当前建议：保留旧实现。** 以下只汇总输入日志中的实际计时，尚不能证明内存和真机交互也更优。\n")
    print("时间单位为毫秒（ms），越小越好；减少耗时和改善比例为正数时，代表候选更快。缺失数据不记为 0。\n")
    print("| 功能 | 资源数量 | 操作 | 轮数 | 原实现 ms | 新候选 ms | 减少耗时 ms | 改善比例 | 最差单轮是否变慢 | 建议 |")
    print("| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |")
    for experiment in EXPERIMENTS:
        for size in SIZES:
            for scenario in SCENARIOS:
                rows = groups.get((experiment, size, scenario), {})
                if set(rows) != SAMPLES:
                    errors.append(f"数据不完整：{NAMES[experiment]}／{size}／{SCENARIO_NAMES[scenario]}。")
                    print(f"| {NAMES[experiment]} | {size:,} | {SCENARIO_NAMES[scenario]} | {len(rows)}/5 | 待测 | 待测 | 无法计算 | 无法计算 | 无法判断 | 保留旧方案 |")
                    continue
                ordered = [rows[index] for index in sorted(SAMPLES)]
                original = statistics.median(row["baseline_ns"] for row in ordered)
                candidate = statistics.median(row["candidate_ns"] for row in ordered)
                worst_ratio = max(row["candidate_ns"] / row["baseline_ns"] for row in ordered)
                equivalent = all(row["equivalent"] for row in ordered)
                improvement = (original - candidate) / original * 100
                improvement_text = "≥99.9%" if improvement >= 99.95 else f"{improvement:.1f}%"
                if not equivalent:
                    result = "拒绝候选：结果不一致"
                    errors.append(f"结果不一致：{NAMES[experiment]}／{size}／{SCENARIO_NAMES[scenario]}。")
                elif candidate >= original or worst_ratio > 1:
                    result = "保留旧方案：有退化或未证明改善"
                elif candidate > original * 0.9:
                    result = "保留旧方案：改善不足 10%"
                else:
                    result = "计时更优；等内存及真机验证后再决定"
                print(
                    f"| {NAMES[experiment]} | {size:,} | {SCENARIO_NAMES[scenario]} | 5 | {original / 1e6:.6f} | "
                    f"{candidate / 1e6:.6f} | {(original - candidate) / 1e6:.6f} | "
                    f"{improvement_text} | "
                    f"{'是，候选耗时为原来的 ' + format(worst_ratio, '.3f') + ' 倍' if worst_ratio > 1 else '否'} | {result} |"
                )

    print("\n原、新耗时取各自 5 轮中位数；改善比例 =（原耗时－新耗时）÷ 原耗时。最差单轮比较配对的新旧耗时。")
    print("5 轮只描述本次运行，不能当作 p95 或统计显著性结论。")
    print("小于 0.01 ms 的短查询仅作参考，不能据此宣称零开销或整页提升数万倍；优先看包含首次准备的总成本。")
    print("\n日期分组：准备后查询 1 次；首次准备＋全部交互共读取 5 次。")
    print("快速清理：首次准备后全选汇总 1 次；其余两种场景各查询 16 次。")
    print("准备完成后的查询不计初始化；首次准备＋全部交互包含初始化。")
    print("快速清理仅比较冻结容量估算下的集合统计，不计 PhotoKit 和容量校准；日期分组不计元数据获取、缩略图或 UI 绘制。")
    print("\n**还缺少：** 峰值内存、真实页面失效重建、能耗和真机端到端延迟。这些证据不足时，即使部分计时更快也不批准替换。")
    print("\n**最终决定：继续原实现。** 本工具只列出证据，不自动切换代码。")
    if errors:
        print("\n测量证据存在以下问题：\n")
        for error in errors:
            print(f"- {error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
