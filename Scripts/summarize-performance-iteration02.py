#!/usr/bin/env python3
"""Read one completed iteration-02 log; do not execute tests or enable candidates."""

import argparse
from collections import defaultdict
import json
from pathlib import Path
import statistics


SHAPES = {
    "shuffled": "乱序", "ascending": "已升序", "descending": "已降序",
    "duplicates": "大量重复值", "organPipe": "先升后降",
}
MEDIAN_SIZES = (32, 1_000, 10_000, 100_000)
QUEUE_SIZES = (1, 2, 8, 32, 1_000, 10_000, 50_000)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    records = []
    for line in args.log.read_text().splitlines():
        if "PERF_ITERATION02_JSON " in line:
            records.append(json.loads(line.split("PERF_ITERATION02_JSON ", 1)[1]))

    expected = {( "calibration-median", size, shape, sample)
                for size in MEDIAN_SIZES for shape in SHAPES for sample in range(5)}
    expected.update(("import-waiter-fifo", size, "enqueue-and-drain", sample)
                    for size in QUEUE_SIZES for sample in range(5))
    keys = {(r["experiment"], r["asset_count"], r["scenario"], r["sample"]) for r in records}
    if len(records) != len(expected) or keys != expected:
        parser.error("记录缺失或重复；必须使用一次完整运行的 135 组数据")
    if any(r["equivalent"] is not True or r["baseline_ns"] <= 0 or r["candidate_ns"] <= 0 for r in records):
        parser.error("存在结果不一致或非法耗时，不能生成通过结论")

    groups = defaultdict(list)
    for row in records:
        groups[row["experiment"], row["asset_count"], row["scenario"]].append(row)

    def values(key):
        rows = groups[key]
        old = statistics.median(r["baseline_ns"] for r in rows) / 1e6
        new = statistics.median(r["candidate_ns"] for r in rows) / 1e6
        gain = (old - new) / old * 100
        worst = max(r["candidate_ns"] / r["baseline_ns"] for r in rows)
        result = "计时更优，仍需完整路径验证" if gain >= 10 and worst <= 1 else "保留原实现"
        return old, new, gain, worst, result

    print("# 性能迭代 02：全部实测时间\n")
    print("同一 Release 运行，关闭覆盖率；每行取 5 轮中位数，交替旧、新执行顺序。135 组结果全部一致。")
    print("正改善比例表示更快，负数表示更慢；5 轮不是 p95，也不能证明统计显著性。\n")
    print("## 容量校准：单个样本组的中位数\n")
    print("| 样本数 | 分布 | 原排序 ms | 新候选 ms | 改善比例 | 最差配对耗时比 | 建议 |")
    print("| ---: | --- | ---: | ---: | ---: | ---: | --- |")
    for size in MEDIAN_SIZES:
        for shape, label in SHAPES.items():
            old, new, gain, worst, result = values(("calibration-median", size, shape))
            print(f"| {size:,} | {label} | {old:.6f} | {new:.6f} | {gain:.1f}% | {worst:.3f}× | {result} |")
    print("\n此处不包含 PhotoKit、样本分组、图片元数据读取或 UI。32 个样本的微秒级差值仅作参考。")
    print("新候选对小样本和抽样判断可能有序的输入复用旧排序，其余执行带排序回退的选择算法；没有改变中位数定义。\n")

    print("## 转换导入：完整入队并清空\n")
    print("| 每轮队列长度 | 每次计时重复轮数 | 原数组总计 ms | FIFO 候选总计 ms | 改善比例 | 最差配对耗时比 | 建议 |")
    print("| ---: | ---: | ---: | ---: | ---: | ---: | --- |")
    for size in QUEUE_SIZES:
        key = ("import-waiter-fifo", size, "enqueue-and-drain")
        old, new, gain, worst, result = values(key)
        cycles = groups[key][0]["cycles"]
        print(f"| {size:,} | {cycles} | {old:.6f} | {new:.6f} | {gain:.1f}% | {worst:.3f}× | {result} |")
    first = groups["import-waiter-fifo", QUEUE_SIZES[0], "enqueue-and-drain"][0]
    print(f"\n本次 Int 元素布局：原槽位 {first['baseline_element_stride']} 字节，候选 Optional 槽位 {first['candidate_element_stride']} 字节。")
    print("这不是峰值 RSS，也不能外推为 CheckedContinuation 的元素布局；本次没有给真实导入等待任务计时。")
    print("两种生命周期都在 Package 内执行，保持相同跨模块调用边界。这里不计媒体读取、转换、actor 调度或热状态策略。")
    print("\n**发布决定：仍使用原实现。** 大队列或单一输入形态的收益，不能抵消常见小队列、其他形态或内存的退化。")


if __name__ == "__main__":
    main()
