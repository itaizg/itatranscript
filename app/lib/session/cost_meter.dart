import 'dart:convert';

import 'settings_store.dart';

/// How close the month's spending is to the cap (FR-014/015).
enum CostLevel {
  /// No cap, or well under it.
  ok,

  /// At or above 90% of the cap: warn once.
  warn90,

  /// At or above the cap: the user must choose to continue or switch to a free engine.
  capReached,
}

/// Tracks spending per calendar month from `usage` events and the engine's price.
class CostMeter {
  /// Creates a meter; [capUsd] null means no cap (the default).
  CostMeter({
    required this.capUsd,
    required this._store,
    Map<String, double>? months,
  }) : _months = <String, double>{...?months};

  /// Loads the saved monthly totals.
  static Future<CostMeter> load({
    required double? capUsd,
    required KeyValueStore store,
  }) async {
    final String? raw = await store.read(_key);
    final Map<String, double> months = <String, double>{};
    if (raw != null) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          for (final MapEntry<String, Object?> e in decoded.entries) {
            final Object? v = e.value;
            if (v is num) {
              months[e.key] = v.toDouble();
            }
          }
        }
      } on FormatException {
        // A corrupt file starts the month from zero; losing a total is safer than crashing.
      }
    }
    return CostMeter(capUsd: capUsd, store: store, months: months);
  }

  static const String _key = 'cost.months.v1';

  /// Monthly cap in USD, or null for none.
  final double? capUsd;
  final KeyValueStore _store;
  final Map<String, double> _months;
  final Set<String> _warned = <String>{};
  final Set<String> _continued = <String>{};

  static String _month(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}';

  /// Spending so far in [now]'s calendar month.
  double spentUsd(DateTime now) => _months[_month(now)] ?? 0;

  /// Adds [audioSeconds] of billed audio at [usdPerHour] and returns the level reached.
  Future<CostLevel> add({
    required double audioSeconds,
    required double usdPerHour,
    required DateTime now,
  }) async {
    final String month = _month(now);
    _months[month] = (_months[month] ?? 0) + audioSeconds / 3600 * usdPerHour;
    await _store.write(_key, jsonEncode(_months));
    return level(now);
  }

  /// The level for [now]'s month, with each warning reported once.
  CostLevel level(DateTime now) {
    final double? cap = capUsd;
    if (cap == null || cap <= 0) {
      return CostLevel.ok;
    }
    final String month = _month(now);
    final double spent = spentUsd(now);
    if (spent >= cap && !_continued.contains(month)) {
      return CostLevel.capReached;
    }
    if (spent >= cap * 0.9 && _warned.add(month)) {
      return CostLevel.warn90;
    }
    return CostLevel.ok;
  }

  /// The user chose to carry on past the cap this month.
  void continuePastCap(DateTime now) => _continued.add(_month(now));
}
