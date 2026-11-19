import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import '../models/engine_profile.dart';
import '../models/pipeline_config.dart';

/// Parses `shared/engines.yaml` into profiles keyed by id, enforcing every load-time rule.
Map<String, EngineProfile> parseEngines(String yamlText) {
  final Object? decoded = jsonDecode(jsonEncode(loadYaml(yamlText)));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('engines.yaml: expected an object');
  }
  final Object? list = decoded['engines'];
  if (list is! List<Object?>) {
    throw const FormatException('engines.yaml: engines must be a list');
  }
  final Map<String, EngineProfile> byId = <String, EngineProfile>{};
  for (final Object? item in list) {
    final EngineProfile p = EngineProfile.fromJson(item);
    if (byId.containsKey(p.id)) {
      throw FormatException('engines.yaml: duplicate engine id ${p.id}');
    }
    byId[p.id] = p;
  }
  return Map<String, EngineProfile>.unmodifiable(byId);
}

/// Parses `shared/pipeline.yaml` and checks the VAD model bytes against `vad.model_sha256`.
PipelineConfig parsePipeline(String yamlText, Uint8List modelBytes) {
  final PipelineConfig config = PipelineConfig.fromJson(
    jsonDecode(jsonEncode(loadYaml(yamlText))),
  );
  final String actual = sha256.convert(modelBytes).toString();
  if (actual != config.vad.modelSha256) {
    throw FormatException(
      'VAD model sha256 mismatch: $actual != ${config.vad.modelSha256}',
    );
  }
  return config;
}
