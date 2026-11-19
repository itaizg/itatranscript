import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:itatranscript/models/audio_frame.dart';

/// `app/assets/shared` is a symlink to the repo's `shared/` folder.
const String sharedDir = 'assets/shared';

String readShared(String relative) =>
    File('$sharedDir/$relative').readAsStringSync();

Object? readSharedJson(String relative) => jsonDecode(readShared(relative));

Uint8List readSharedBytes(String relative) =>
    File('$sharedDir/$relative').readAsBytesSync();

/// Raw s16le samples of a 16 kHz mono 16-bit WAV (walks the chunks to find `data`).
Uint8List readWavPcm(String relative) {
  final Uint8List bytes = readSharedBytes(relative);
  final ByteData view = ByteData.sublistView(bytes);
  int pos = 12;
  while (pos + 8 <= bytes.length) {
    final String id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final int size = view.getUint32(pos + 4, Endian.little);
    if (id == 'data') {
      return Uint8List.sublistView(bytes, pos + 8, pos + 8 + size);
    }
    pos += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw FormatException('$relative: no data chunk');
}

/// 20 ms frames of [pcm], zero-padded at the end, plus [tailMs] of silence.
List<AudioFrame> framesOf(Uint8List pcm, {int tailMs = 0}) {
  final int total =
      ((pcm.length + tailMs ~/ kFrameMs * kFrameBytes) / kFrameBytes).ceil();
  final Uint8List padded = Uint8List(total * kFrameBytes)..setAll(0, pcm);
  return <AudioFrame>[
    for (int i = 0; i < total; i++)
      AudioFrame(
        seq: i,
        tMs: i * kFrameMs,
        pcm: Uint8List.sublistView(
          padded,
          i * kFrameBytes,
          (i + 1) * kFrameBytes,
        ),
      ),
  ];
}

/// Every `*.events.jsonl` fixture under `shared/fixtures`, including `native/`.
List<File> eventFixtures() =>
    Directory('$sharedDir/fixtures')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.events.jsonl'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));

/// Casts decoded JSON to an object.
Map<String, Object?> asMap(Object? v) =>
    (v! as Map<Object?, Object?>).cast<String, Object?>();

/// Casts decoded JSON to a list.
List<Object?> asList(Object? v) => v! as List<Object?>;
