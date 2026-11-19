import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itatranscript/models/engine_event.dart';
import 'package:json_schema/json_schema.dart';

import 'support.dart';

void main() {
  final JsonSchema schema = JsonSchema.create(
    readShared('engine-events.schema.json'),
  );
  final List<File> fixtures = eventFixtures();

  test('there are fixtures to check', () {
    expect(fixtures.length, greaterThanOrEqualTo(5));
  });

  for (final File file in fixtures) {
    test(
      '${file.path.split('fixtures/').last}: schema and model agree on every line',
      () {
        for (final String line in const LineSplitter().convert(
          file.readAsStringSync(),
        )) {
          if (line.trim().isEmpty) {
            continue;
          }
          final Object? json = jsonDecode(line);
          expect(schema.validate(json).isValid, isTrue, reason: line);
          final EngineEvent event = EngineEvent.fromJson(json);
          expect(
            jsonDecode(jsonEncode(event.toJson())),
            json,
            reason: 'round trip: $line',
          );
        }
      },
    );
  }

  test('a renamed field is rejected by both the schema and the model', () {
    final Map<String, Object?> good = <String, Object?>{
      'type': 'partial',
      't_ms': 1,
      'segment_id': 's1',
      'text': 'hi',
      'start_ms': 0,
    };
    final Map<String, Object?> renamed = <String, Object?>{...good}
      ..remove('segment_id')
      ..['segmentId'] = 's1';
    expect(schema.validate(good).isValid, isTrue);
    expect(schema.validate(renamed).isValid, isFalse);
    expect(() => EngineEvent.fromJson(renamed), throwsFormatException);
  });

  test('unknown types and bad values are rejected', () {
    expect(
      () => EngineEvent.fromJson(<String, Object?>{'type': 'nope', 't_ms': 0}),
      throwsFormatException,
    );
    expect(
      () =>
          EngineEvent.fromJson(<String, Object?>{'type': 'closed', 't_ms': -1}),
      throwsFormatException,
    );
    expect(
      () => EngineEvent.fromJson(<String, Object?>{
        'type': 'closed',
        't_ms': 0,
        'extra': 1,
      }),
      throwsFormatException,
    );
  });

  test('events have value equality', () {
    const ClosedEvent a = ClosedEvent(tMs: 5);
    expect(a, const ClosedEvent(tMs: 5));
    expect(a == const ClosedEvent(tMs: 6), isFalse);
  });
}
