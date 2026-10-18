#!/usr/bin/env python3
"""Read completed iteration-04 logs; never executes tests or promotes candidates."""
import argparse
import collections
import json
import statistics
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('log', type=Path)
args = parser.parse_args()
text = args.log.read_text()
if 'Test run with 3 tests in 1 suite passed' not in text or '** TEST EXECUTE SUCCEEDED **' not in text:
    raise SystemExit('The complete three-test suite did not report success.')
rows = [json.loads(line[7:]) for line in text.splitlines() if line.startswith('PERF04 ')]
expected = {('media-queue', n, 'fifo', r) for n in [1, 8, 32, 1000, 10000, 50000] for r in range(5)}
expected |= {('batch-order', n, s, r) for n in [8, 1000, 100000] for s in ['ascending', 'descending', 'shuffled', 'sparse'] for r in range(5)}
keys = [(r['experiment'], r['count'], r['shape'], r['round']) for r in rows]
if len(rows) != 90 or set(keys) != expected or len(set(keys)) != len(rows):
    raise SystemExit('Missing or duplicate comparison records.')
if not all(r['equal'] is True and r['old_ns'] > 0 and r['new_ns'] > 0 for r in rows):
    raise SystemExit('Incorrect output or invalid timing.')
groups = collections.defaultdict(list)
for r in rows:
    groups[r['experiment'], r['count'], r['shape']].append(r)
print('| 场景 | 数量 | 分布 | 循环次数 | 旧 ms | 新 ms | 耗时降低 |')
print('|---|---:|---|---:|---:|---:|---:|')
for (experiment, count, shape), group in groups.items():
    old = statistics.median(r['old_ns'] for r in group) / 1e6
    new = statistics.median(r['new_ns'] for r in group) / 1e6
    print(f'| {experiment} | {count:,} | {shape} | {group[0]["cycles"]} | {old:.6f} | {new:.6f} | {(1-new/old)*100:.1f}% |')
print('\n负数表示退步。小队列为 1,000 次完整生命周期合计；正式实现保持不变。')
