import 'package:battery_plus/battery_plus.dart';

import '../models/pipeline_config.dart';

/// A reading of the battery.
class BatteryReading {
  /// Creates a reading.
  const BatteryReading({required this.percent, required this.charging});

  /// Charge, 0–100.
  final int percent;

  /// Whether the device is plugged in.
  final bool charging;
}

/// Reads the battery (the plugin in the app; a fake in tests).
abstract interface class BatteryReader {
  /// The current reading.
  Future<BatteryReading> read();
}

/// [BatteryReader] on `battery_plus`.
class PlatformBatteryReader implements BatteryReader {
  /// Creates a reader.
  PlatformBatteryReader() : _battery = Battery();

  final Battery _battery;

  @override
  Future<BatteryReading> read() async {
    final int level = await _battery.batteryLevel;
    final BatteryState state = await _battery.batteryState;
    return BatteryReading(
      percent: level,
      charging: state == BatteryState.charging || state == BatteryState.full,
    );
  }
}

/// Why the warning fired.
enum BatteryWarningKind {
  /// The measured drain says the battery will last under the configured minutes.
  minutesLeft,

  /// The charge is at or below the configured percentage.
  percent,
}

/// A battery-low warning (spec edge case, research R-18).
class BatteryWarning {
  /// Creates a warning; [minutesLeft] is null when it could not be estimated.
  const BatteryWarning({
    required this.kind,
    required this.percent,
    this.minutesLeft,
  });

  /// Which threshold fired.
  final BatteryWarningKind kind;

  /// Charge when it fired.
  final int percent;

  /// Estimated minutes left at the measured drain rate.
  final int? minutesLeft;
}

/// Measures the drain rate and applies the thresholds from `pipeline.yaml`.
class BatteryWatch {
  /// Creates a watch.
  BatteryWatch(this._config);

  final PipelineConfig _config;
  int? _startPercent;
  int? _startMs;

  /// The percentage at the first sample.
  int? get startPercent => _startPercent;

  /// Adds a sample at [nowMs]; returns a warning if a threshold is crossed (never while charging).
  BatteryWarning? sample(BatteryReading reading, int nowMs) {
    _startPercent ??= reading.percent;
    _startMs ??= nowMs;
    if (reading.charging) {
      return null;
    }
    final int? minutes = _minutesLeft(reading.percent, nowMs);
    if (minutes != null && minutes < _config.batteryMinRemainingMinutes) {
      return BatteryWarning(
        kind: BatteryWarningKind.minutesLeft,
        percent: reading.percent,
        minutesLeft: minutes,
      );
    }
    if (reading.percent <= _config.batteryMinPercent) {
      return BatteryWarning(
        kind: BatteryWarningKind.percent,
        percent: reading.percent,
        minutesLeft: minutes,
      );
    }
    return null;
  }

  int? _minutesLeft(int percent, int nowMs) {
    final int dropped = (_startPercent ?? percent) - percent;
    final int elapsedMs = nowMs - (_startMs ?? nowMs);
    if (dropped <= 0 || elapsedMs <= 0) {
      return null;
    }
    final double msPerPercent = elapsedMs / dropped;
    return (percent * msPerPercent / 60000).floor();
  }
}
