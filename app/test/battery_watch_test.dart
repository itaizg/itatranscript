import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/engines/profiles.dart';
import 'package:itatranscript/session/battery_watch.dart';

import 'support.dart';

void main() {
  final config = parsePipeline(
    readShared('pipeline.yaml'),
    readSharedBytes('models/silero_vad.onnx'),
  );
  const int minute = 60000;

  test('warns when the measured drain leaves under 20 minutes', () {
    final BatteryWatch w = BatteryWatch(config);
    expect(
      w.sample(const BatteryReading(percent: 50, charging: false), 0),
      isNull,
    );
    // 10 percent in 10 minutes = 1 %/min, so 40 % left is 40 min: no warning yet.
    expect(
      w.sample(const BatteryReading(percent: 40, charging: false), 10 * minute),
      isNull,
    );
    // 30 % at minute 20 (1 %/min) leaves 30 min; at 19 % (minute 31) it leaves 19 min.
    final BatteryWarning? warning = w.sample(
      const BatteryReading(percent: 19, charging: false),
      31 * minute,
    );
    expect(warning?.kind, BatteryWarningKind.minutesLeft);
    expect(warning?.minutesLeft, 19);
  });

  test(
    'warns at or below the percent threshold even with no drain estimate',
    () {
      final BatteryWatch w = BatteryWatch(config);
      final BatteryWarning? warning = w.sample(
        const BatteryReading(percent: 10, charging: false),
        0,
      );
      expect(warning?.kind, BatteryWarningKind.percent);
      expect(warning?.minutesLeft, isNull);
    },
  );

  test('never warns while charging', () {
    final BatteryWatch w = BatteryWatch(config);
    expect(
      w.sample(const BatteryReading(percent: 5, charging: true), 0),
      isNull,
    );
  });

  test('a flat battery gives no drain estimate and no warning', () {
    final BatteryWatch w = BatteryWatch(config);
    w.sample(const BatteryReading(percent: 80, charging: false), 0);
    expect(
      w.sample(const BatteryReading(percent: 80, charging: false), 60 * minute),
      isNull,
    );
  });

  test('the thresholds come from pipeline.yaml', () {
    expect(config.batteryMinRemainingMinutes, 20);
    expect(config.batteryMinPercent, 10);
  });
}
