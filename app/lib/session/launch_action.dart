/// What the app should do right after it launches (FR-011).
sealed class LaunchAction {
  const LaunchAction();
}

/// Start captions now (opened from the Lock Screen control, a Shortcut or the widget).
final class StartSession extends LaunchAction {
  /// Creates the action.
  const StartSession();
}

/// The last session was cut off by the OS; tell the user when.
final class ShowStoppedNotice extends LaunchAction {
  /// Creates the action; [stoppedAt] is the last time the session was seen alive.
  const ShowStoppedNotice(this.stoppedAt);

  /// When captions stopped.
  final DateTime stoppedAt;

  /// `HH:MM`, as shown in the notice.
  String get label =>
      '${stoppedAt.hour.toString().padLeft(2, '0')}:${stoppedAt.minute.toString().padLeft(2, '0')}';
}

/// Nothing special: show the idle caption screen.
final class NoAction extends LaunchAction {
  /// Creates the action.
  const NoAction();
}

/// Chooses the launch action from the launch arguments and the last stats entry.
///
/// A start request wins. Otherwise, an `os_killed` last session becomes a notice.
LaunchAction decideLaunchAction({
  required Map<String, String> launchArguments,
  required Map<String, Object?>? lastStats,
}) {
  if (launchArguments['start'] == 'true') {
    return const StartSession();
  }
  if (lastStats != null && lastStats['end_reason'] == 'os_killed') {
    final Object? started = lastStats['started_at'];
    final Object? duration = lastStats['duration_s'];
    if (started is String && duration is int) {
      final DateTime? start = DateTime.tryParse(started);
      if (start != null) {
        return ShowStoppedNotice(
          start.add(Duration(seconds: duration)).toLocal(),
        );
      }
    }
  }
  return const NoAction();
}
