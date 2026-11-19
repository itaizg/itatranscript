import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/session/cost_meter.dart';

import 'fakes.dart';

void main() {
  final DateTime nov = DateTime(2026, 11, 15);
  final DateTime dec = DateTime(2026, 12, 2);

  test('usage × price accumulates within a calendar month', () async {
    final CostMeter m = CostMeter(capUsd: null, store: MemoryKeyValueStore());
    await m.add(audioSeconds: 1800, usdPerHour: 2, now: nov);
    await m.add(audioSeconds: 1800, usdPerHour: 2, now: nov);
    expect(m.spentUsd(nov), closeTo(2.0, 1e-9));
  });

  test('a new calendar month starts from zero', () async {
    final CostMeter m = CostMeter(capUsd: 10, store: MemoryKeyValueStore());
    await m.add(audioSeconds: 3600, usdPerHour: 4, now: nov);
    expect(m.spentUsd(dec), 0);
    expect(m.spentUsd(nov), 4);
  });

  test('warns once at 90% and requires a decision at 100%', () async {
    final CostMeter m = CostMeter(capUsd: 10, store: MemoryKeyValueStore());
    expect(
      await m.add(audioSeconds: 3600, usdPerHour: 8, now: nov),
      CostLevel.ok,
    );
    expect(
      await m.add(audioSeconds: 3600, usdPerHour: 1.5, now: nov),
      CostLevel.warn90,
    );
    expect(
      await m.add(audioSeconds: 360, usdPerHour: 1, now: nov),
      CostLevel.ok,
      reason: 'only once',
    );
    expect(
      await m.add(audioSeconds: 3600, usdPerHour: 1, now: nov),
      CostLevel.capReached,
    );
    expect(
      m.level(nov),
      CostLevel.capReached,
      reason: 'stays until the user decides',
    );
    m.continuePastCap(nov);
    expect(m.level(nov), CostLevel.ok);
  });

  test('no warnings when the cap is null', () async {
    final CostMeter m = CostMeter(capUsd: null, store: MemoryKeyValueStore());
    expect(
      await m.add(audioSeconds: 360000, usdPerHour: 100, now: nov),
      CostLevel.ok,
    );
  });

  test('totals survive a restart', () async {
    final MemoryKeyValueStore store = MemoryKeyValueStore();
    final CostMeter a = CostMeter(capUsd: 5, store: store);
    await a.add(audioSeconds: 3600, usdPerHour: 3, now: nov);
    final CostMeter b = await CostMeter.load(capUsd: 5, store: store);
    expect(b.spentUsd(nov), 3);
  });

  test('a corrupt saved file starts from zero instead of crashing', () async {
    final MemoryKeyValueStore store = MemoryKeyValueStore()
      ..data['cost.months.v1'] = '{oops';
    expect((await CostMeter.load(capUsd: 5, store: store)).spentUsd(nov), 0);
  });
}
