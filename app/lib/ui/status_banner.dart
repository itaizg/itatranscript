import 'package:material_ui/material_ui.dart';

import '../models/session_snapshot.dart';

/// What to show in the banner, as plain data so it can be tested.
class BannerSpec {
  /// Creates a spec.
  const BannerSpec({
    required this.key,
    required this.text,
    required this.color,
  });

  /// Stable id for tests.
  final String key;

  /// The message.
  final String text;

  /// Amber for degraded service, red for stopped.
  final Color color;
}

const Color _amber = Color(0xFFB26A00);
const Color _red = Color(0xFF9C1C1C);

/// Picks the banner for a snapshot (FR-021), most urgent first.
BannerSpec? bannerFor(SessionSnapshot s, {String? stoppedNotice}) {
  if (s.errorMessage != null && s.state == SessionState.ended) {
    return BannerSpec(key: 'error', text: s.errorMessage!, color: _red);
  }
  switch (s.state) {
    case SessionState.pausedOffline:
      return const BannerSpec(
        key: 'paused_offline',
        text: 'captions paused – no connection',
        color: _red,
      );
    case SessionState.pausedMic:
      final String reason = s.pauseReason ?? 'mic in use';
      return BannerSpec(
        key: 'paused_mic',
        text: 'paused – mic in use ($reason)',
        color: _red,
      );
    case SessionState.fallback:
      return const BannerSpec(
        key: 'fallback',
        text: 'offline – lower accuracy',
        color: _amber,
      );
    case SessionState.idle ||
        SessionState.starting ||
        SessionState.live ||
        SessionState.ended:
      break;
  }
  if (s.batteryLow) {
    final int? minutes = s.batteryMinutesLeft;
    final String left = minutes == null ? '' : ' – about $minutes min left';
    return BannerSpec(key: 'battery', text: 'battery low$left', color: _amber);
  }
  if (s.costLevel == 'warn90') {
    return const BannerSpec(
      key: 'cost_warn',
      text: 'near your monthly cap',
      color: _amber,
    );
  }
  if (stoppedNotice != null) {
    return BannerSpec(
      key: 'os_kill',
      text: 'captions stopped at $stoppedNotice',
      color: _amber,
    );
  }
  return null;
}

/// Renders a [BannerSpec] above the caption list (never over the newest line).
class StatusBanner extends StatelessWidget {
  /// Creates the banner; renders nothing when [spec] is null.
  const StatusBanner({required this.spec, super.key});

  /// What to show.
  final BannerSpec? spec;

  @override
  Widget build(BuildContext context) {
    final BannerSpec? s = spec;
    if (s == null) {
      return const SizedBox.shrink();
    }
    return Container(
      key: Key('banner_${s.key}'),
      width: double.infinity,
      color: s.color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        s.text,
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }
}
