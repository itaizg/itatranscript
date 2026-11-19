import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/caption_segment.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _clock(int ms) {
  final int s = ms ~/ 1000;
  return '[${_two(s ~/ 3600)}:${_two(s % 3600 ~/ 60)}:${_two(s % 60)}]';
}

/// The export file name: `captions-YYYY-MM-DD-HHmm.txt`.
String exportFileName(DateTime startedAt) =>
    'captions-${startedAt.year}-${_two(startedAt.month)}-${_two(startedAt.day)}-'
    '${_two(startedAt.hour)}${_two(startedAt.minute)}.txt';

/// Builds the export body (`contracts/export-format.md`): finals only, logical-order text.
String buildTranscript({
  required List<CaptionSegment> segments,
  required DateTime startedAt,
  required Duration duration,
  required String engineId,
  required String mode,
  Map<String, Object?>? statsWhenTestMode,
}) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes % 60;
  final String length = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  final StringBuffer out = StringBuffer(
    '# Captions – ${startedAt.year}-${_two(startedAt.month)}-${_two(startedAt.day)} '
    '${_two(startedAt.hour)}:${_two(startedAt.minute)} ($length) · engine: $engineId · mode: $mode\n\n',
  );
  EngineRole? previous;
  for (final CaptionSegment s in segments.where(
    (CaptionSegment s) => s.status == SegmentStatus.finalized,
  )) {
    if (s.engineRole == EngineRole.fallback &&
        previous != EngineRole.fallback) {
      out.writeln('${_clock(s.startMs)} (offline – lower accuracy)');
    }
    previous = s.engineRole;
    if (s.speakerChangeBefore) {
      out.writeln('${_clock(s.startMs)} — speaker change —');
    }
    out.writeln(
      '${_clock(s.startMs)} ${s.isUnrecognized ? '[unrecognized]' : s.text}',
    );
  }
  if (statsWhenTestMode != null) {
    out
      ..writeln()
      ..writeln('--- session stats ---')
      ..writeln(jsonEncode(statsWhenTestMode));
  }
  return out.toString();
}

/// Opens the share sheet for a file.
abstract interface class Sharer {
  /// Shows the share sheet for [path]; completes when it closes.
  Future<void> share(String path);
}

/// [Sharer] on `share_plus`.
class SharePlusSharer implements Sharer {
  /// Creates the sharer.
  const SharePlusSharer();

  @override
  Future<void> share(String path) async {
    await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(path)]));
  }
}

/// Where the temporary export file lives.
typedef TempDirProvider = Future<Directory> Function();

/// A visible failure while exporting (VIII).
class ExportFailure implements Exception {
  /// Creates the failure.
  const ExportFailure(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ExportFailure: $message';
}

/// Writes a temp file, shares it, and deletes it: the single owner of the temp file.
class TranscriptExporter {
  /// Creates an exporter; defaults use `path_provider` and `share_plus`.
  const TranscriptExporter({
    this.sharer = const SharePlusSharer(),
    this.tempDir = getTemporaryDirectory,
  });

  /// Share sheet.
  final Sharer sharer;

  /// Temp directory source.
  final TempDirProvider tempDir;

  /// Exports [body] as [fileName]; the temp file is removed even when sharing fails.
  Future<void> export({required String fileName, required String body}) async {
    final Directory dir = await tempDir();
    final File file = File('${dir.path}/$fileName');
    try {
      await file.writeAsString(body, flush: true);
      await sharer.share(file.path);
    } on Object catch (error) {
      throw ExportFailure('could not export: ${error.runtimeType}');
    } finally {
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }
}
