import 'package:material_ui/material_ui.dart';

import '../session/session_stats.dart';

/// Lists the stored session stats with delete (FR-023). Stats never contain text.
class StatsScreen extends StatefulWidget {
  /// Creates the screen.
  const StatsScreen({required this.store, super.key});

  /// Where the stats live.
  final StatsStore store;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<List<Map<String, Object?>>> _rows = widget.store.readAll();

  void _reload() => setState(() => _rows = widget.store.readAll());

  static String _ms(Object? latency) {
    if (latency is Map<String, Object?> && latency['p50'] != null) {
      return '${latency['p50']} / ${latency['p90']} ms (n=${latency['n']})';
    }
    return '–';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session stats'),
        actions: <Widget>[
          TextButton(
            key: const Key('delete_all'),
            onPressed: () async {
              await widget.store.deleteAll();
              _reload();
            },
            child: const Text('Delete all'),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _rows,
        builder: (BuildContext context, AsyncSnapshot<List<Map<String, Object?>>> snap) {
          final List<Map<String, Object?>> rows =
              snap.data ?? const <Map<String, Object?>>[];
          if (rows.isEmpty) {
            return const Center(child: Text('No sessions recorded.'));
          }
          return ListView(
            children: <Widget>[
              for (final Map<String, Object?> r in rows.reversed)
                ListTile(
                  key: Key('stat_${r['session_id']}'),
                  title: Text(
                    '${r['started_at']} · ${r['duration_s']} s · ${r['end_reason']}',
                  ),
                  subtitle: Text(
                    'engine ${r['active_engine_id'] ?? '–'} · provisional ${_ms(r['provisional_ms'])} · '
                    'final ${_ms(r['final_ms'])}',
                  ),
                  trailing: IconButton(
                    key: Key('delete_${r['session_id']}'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.store.deleteOne('${r['session_id']}');
                      _reload();
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
