import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/session/launch_action.dart';

void main() {
  test('start=true starts a session, even after an OS kill', () {
    final LaunchAction a = decideLaunchAction(
      launchArguments: <String, String>{'start': 'true'},
      lastStats: <String, Object?>{'end_reason': 'os_killed'},
    );
    expect(a, isA<StartSession>());
  });

  test('an OS-killed last session becomes a "stopped at HH:MM" notice', () {
    final LaunchAction a = decideLaunchAction(
      launchArguments: const <String, String>{},
      lastStats: <String, Object?>{
        'end_reason': 'os_killed',
        'started_at': '2026-12-01T19:02:11Z',
        'duration_s': 3600,
      },
    );
    expect(a, isA<ShowStoppedNotice>());
    final DateTime stopped = (a as ShowStoppedNotice).stoppedAt;
    expect(stopped.toUtc(), DateTime.utc(2026, 12, 1, 20, 2, 11));
    expect(a.label, matches(RegExp(r'^\d{2}:\d{2}$')));
  });

  test('anything else is no action', () {
    expect(
      decideLaunchAction(
        launchArguments: const <String, String>{},
        lastStats: null,
      ),
      isA<NoAction>(),
    );
    expect(
      decideLaunchAction(
        launchArguments: <String, String>{'start': 'false'},
        lastStats: <String, Object?>{'end_reason': 'user_stop'},
      ),
      isA<NoAction>(),
    );
    expect(
      decideLaunchAction(
        launchArguments: const <String, String>{},
        lastStats: <String, Object?>{
          'end_reason': 'os_killed',
          'started_at': 'garbage',
          'duration_s': 5,
        },
      ),
      isA<NoAction>(),
    );
  });
}
