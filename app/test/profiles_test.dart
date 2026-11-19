import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/core/clock.dart';
import 'package:itatranscript/engines/engine_adapter.dart';
import 'package:itatranscript/engines/profiles.dart';
import 'package:itatranscript/models/engine_profile.dart';

import 'support.dart';

Map<String, Object?> _fake() => <String, Object?>{
  'id': 'x',
  'display_name': 'X',
  'adapter': 'fake',
  'runs_on': 'cloud',
  'platforms': <String>['ios'],
  'languages': <String>['en'],
  'supports_code_switching': false,
  'supports_speaker_changes': false,
  'can_be_fallback': false,
  'cost_usd_per_hour': 1.0,
  'privacy': <String, Object?>{
    'retains_audio': false,
    'trains_on_audio': false,
    'opt_out_required': false,
    'terms_source': 'x',
    'terms_checked_on': 'unverified',
  },
  'options': <String, Object?>{},
};

Map<String, Object?> _with(Map<String, Object?> overrides) => <String, Object?>{
  ..._fake(),
  ...overrides,
};

Map<String, Object?> _privacy(Map<String, Object?> o) => <String, Object?>{
  ...(_fake()['privacy']! as Map<String, Object?>),
  ...o,
};

void main() {
  test('the real engines.yaml loads and every profile is valid', () {
    final Map<String, EngineProfile> engines = parseEngines(
      readShared('engines.yaml'),
    );
    expect(
      engines.keys,
      containsAll(<String>['fake', 'apple-ondevice', 'whisper-ivrit-local']),
    );
  });

  test('load-time rules are enforced', () {
    expect(
      () =>
          EngineProfile.fromJson(_with(<String, Object?>{'runs_on': 'device'})),
      throwsFormatException,
    );
    expect(
      () => EngineProfile.fromJson(
        _with(<String, Object?>{'can_be_fallback': true}),
      ),
      throwsFormatException,
    );
    expect(
      () => EngineProfile.fromJson(
        _with(<String, Object?>{'languages': <String>[]}),
      ),
      throwsFormatException,
    );
    expect(
      () => EngineProfile.fromJson(_with(<String, Object?>{'surprise': 1})),
      throwsFormatException,
    );
  });

  test('the privacy gate refuses a retaining engine, and one that trains with no opt-out', () {
    final EngineProfile retains = EngineProfile.fromJson(
      _with(<String, Object?>{
        'privacy': _privacy(<String, Object?>{'retains_audio': true}),
      }),
    );
    expect(retains.assertOpenable, throwsA(isA<PrivacyGateException>()));
    final EngineProfile trains = EngineProfile.fromJson(
      _with(<String, Object?>{
        'privacy': _privacy(<String, Object?>{'trains_on_audio': true}),
      }),
    );
    expect(trains.assertOpenable, throwsA(isA<PrivacyGateException>()));
    final EngineProfile optOut = EngineProfile.fromJson(
      _with(<String, Object?>{
        'privacy': _privacy(<String, Object?>{
          'trains_on_audio': true,
          'opt_out_required': true,
        }),
      }),
    );
    optOut.assertOpenable();
  });

  test('the registry applies the privacy gate before building an adapter', () {
    final AdapterRegistry registry = AdapterRegistry(<String, AdapterFactory>{
      'fake': (EngineProfile p, Clock c) =>
          throw StateError('must not be built'),
    });
    final EngineProfile retains = EngineProfile.fromJson(
      _with(<String, Object?>{
        'privacy': _privacy(<String, Object?>{'retains_audio': true}),
      }),
    );
    expect(
      () => registry.create(retains, FakeClock()),
      throwsA(isA<PrivacyGateException>()),
    );
    expect(
      () => registry.create(
        EngineProfile.fromJson(_with(<String, Object?>{'adapter': 'nope'})),
        FakeClock(),
      ),
      throwsA(isA<UnknownAdapterException>()),
    );
  });

  test('pipeline.yaml loads, and a wrong model hash is rejected', () {
    final config = parsePipeline(
      readShared('pipeline.yaml'),
      readSharedBytes('models/silero_vad.onnx'),
    );
    expect(config.vad.minSpeechMs, 250);
    expect(config.ringBufferS, 5);
    expect(
      () => parsePipeline(readShared('pipeline.yaml'), Uint8List(4)),
      throwsFormatException,
    );
  });
}
