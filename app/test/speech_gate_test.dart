import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/engines/profiles.dart';
import 'package:itatranscript/gate/silero_onnx_model.dart';
import 'package:itatranscript/gate/speech_gate.dart';
import 'package:itatranscript/models/audio_frame.dart';
import 'package:itatranscript/models/pipeline_config.dart';

import 'support.dart';

/// Replays probabilities recorded from the harness's Silero run (`vad-probs.json`).
class ReplayModel implements VadModel {
  ReplayModel(this._probs);
  final List<double> _probs;
  int _i = 0;

  @override
  double probability(Float32List chunk) => _probs[_i++];
}

void main() {
  final PipelineConfig config = parsePipeline(
    readShared('pipeline.yaml'),
    readSharedBytes('models/silero_vad.onnx'),
  );
  final Map<String, Object?> fixture =
      readSharedJson('fixtures/vad-probs.json')! as Map<String, Object?>;
  final Map<String, Object?> cases = fixture['cases']! as Map<String, Object?>;

  for (final String name in cases.keys) {
    test(
      '$name: the Dart gate matches the harness gate (spans and frames passed)',
      () {
        final Map<String, Object?> c = asMap(cases[name]);
        final SpeechGate gate = SpeechGate(
          ReplayModel(<double>[
            for (final Object? p in c['probs']! as List<Object?>)
              (p! as num).toDouble(),
          ]),
          config.vad,
        );
        int passed = 0;
        for (final AudioFrame f in framesOf(
          readWavPcm('fixtures/${c['wav']}'),
          tailMs: c['tail_ms']! as int,
        )) {
          passed += gate.push(f).length;
        }
        gate.finish();
        final List<List<int>> expected = <List<int>>[
          for (final Object? s in asList(c['spans']))
            <int>[asList(s)[0]! as int, asList(s)[1]! as int],
        ];
        expect(
          gate.spans
              .map((SpeechSpan s) => <int>[s.onsetMs, s.offsetMs!])
              .toList(),
          expected,
        );
        expect(passed, c['frames_passed']);
      },
    );
  }

  test(
    'silence passes 0 frames and finds 0 spans; speech finds at least one span',
    () {
      final Map<String, Object?> silence = asMap(cases['silence-5s']);
      final Map<String, Object?> speech = asMap(cases['speech-short']);
      expect(silence['frames_passed'], 0);
      expect(silence['spans'], isEmpty);
      expect(asList(speech['spans']), isNotEmpty);
    },
  );

  test('wrong model bytes fail the sha256 check', () {
    expect(
      () => parsePipeline(
        readShared('pipeline.yaml'),
        Uint8List.fromList(<int>[1, 2, 3]),
      ),
      throwsFormatException,
    );
  });

  test(
    'the real Silero ONNX model gives the same spans (needs libonnxruntime)',
    () {
      late SileroOnnxModel model;
      try {
        model = SileroOnnxModel(readSharedBytes('models/silero_vad.onnx'));
      } on ArgumentError catch (e) {
        markTestSkipped(
          'libonnxruntime is not loadable in flutter test: ${e.message}'
              .split('\n')
              .first,
        );
        return;
      }
      final SpeechGate gate = SpeechGate(model, config.vad);
      for (final AudioFrame f in framesOf(
        readWavPcm('fixtures/speech-short.wav'),
        tailMs: 1000,
      )) {
        gate.push(f);
      }
      gate.finish();
      final Map<String, Object?> c = asMap(cases['speech-short']);
      final List<Object?> spans = asList(c['spans']);
      expect(gate.spans.length, spans.length);
      expect(gate.spans.first.onsetMs, asList(spans.first)[0]);
      model.release();
    },
    skip: Platform.isWindows,
  );
}
