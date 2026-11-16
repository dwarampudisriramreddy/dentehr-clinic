import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

class DentalCodingAI {
  static bool _initialized = false;

  InferenceModel? _model;
  String? _modelPath;

  bool get isReady => _model != null;
  String? get modelPath => _modelPath;
  String? get modelName => _modelPath?.split(RegExp(r'[\\/]')).last;

  Future<void> initModel({required String modelPath}) async {
    if (!_initialized) {
      await FlutterEdgeAi.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
      );
      _initialized = true;
    }

    if (_model != null) {
      await disposeModel();
    }

    await FlutterEdgeAi.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(modelPath).install();

    _model = await FlutterEdgeAi.getActiveModel(
      maxTokens: 512,
      preferredBackend: PreferredBackend.gpu,
    );
    _modelPath = modelPath;
  }

  Future<String> generate(String prompt, {int maxTokens = 512}) async {
    final model = _model;
    if (model == null) {
      throw StateError('No AI model loaded. Pick a .litertlm model file first.');
    }
    final chat = await model.openChat();
    try {
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      final buffer = StringBuffer();
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) buffer.write(response.token);
      }
      return buffer.toString().trim();
    } finally {
      await chat.close();
    }
  }

  Future<Map<String, dynamic>> extractFacts(String clinicalNote) async {
    final raw = await generate(
      'Extract dental facts from this note.\n'
      'Return ONLY a raw JSON object, no markdown, no explanation.\n'
      'Keys: "tooth" (FDI number string), "surface" (e.g. MO, O, DO), '
      '"material" (e.g. composite, amalgam, crown), '
      '"condition" (one of: caries, missing, treated, pulpitis, abscess, '
      'fracture, periodontitis, attrition, abrasion, root_stump, impacted, normal).\n'
      'Note: "$clinicalNote"\nJSON:',
      maxTokens: 256,
    );
    return _sanitizeJson(raw);
  }

  /// Interpret a dentist prompt as odontogram changes or diagnosis.
  /// Returns {"action":"update"|"diagnose","reply":"...","changes":[{tooth,category},...]}
  Future<Map<String, dynamic>> interpretOdontogramPrompt(
    String prompt,
    String currentSummary,
  ) async {
    final raw = await generate(
      'You are a dental assistant for an odontogram (FDI tooth numbering 11-18,21-28,31-38,41-48).\n'
      'Current chart: $currentSummary\n'
      'User request: "$prompt"\n'
      'Decide action: "update" to change chart, or "diagnose" to only explain/diagnose.\n'
      'Return ONLY raw JSON, no markdown. Schema:\n'
      '{"action":"update|diagnose","reply":"short explanation/diagnosis for dentist","changes":[{"tooth":"16","category":"Decayed"}]}\n'
      'Allowed category values: Decayed,Missing,Treated,Pulpitis,Abscess,Fracture,Periodontitis,Attrition,Abrasion,Root Stump,Impacted,Mobility,Recession,Pocket,Normal.\n'
      'Use "changes":[] if action is diagnose or nothing to change.\nJSON:',
      maxTokens: 512,
    );
    final json = _sanitizeJson(raw);
    json.putIfAbsent('action', () => 'diagnose');
    json.putIfAbsent('reply', () => raw.trim());
    json.putIfAbsent('changes', () => <dynamic>[]);
    return json;
  }

  /// Agent mode: interpret a natural-language command that may create/update a
  /// patient and modify odontogram findings.
  /// Returns {"action":"create_patient|update_patient|odontogram|diagnose",
  /// "reply":"...", "patient":{first_name,last_name,phone,age,sex,chief_complaint,
  /// medical_history,diagnosis,appointment,clinic}, "changes":[{tooth,category},...]}
  Future<Map<String, dynamic>> interpretAgentPrompt(String prompt) async {
    final raw = await generate(
      'You are an agentic dental clinic assistant. Convert the user request into an action plan.\n'
      'User request: "$prompt"\n'
      'Return ONLY raw JSON, no markdown. Schema:\n'
      '{"action":"create_patient|update_patient|odontogram|diagnose","reply":"short confirmation or diagnosis",'
      '"patient":{"first_name":"","last_name":"","phone":"","age":"","sex":"","chief_complaint":"","medical_history":"","diagnosis":"","appointment":"","clinic":""},'
      '"changes":[{"tooth":"31","category":"Pulpitis"}]}\n'
      'Rules: use FDI tooth numbers 11-18,21-28,31-38,41-48. '
      'Allowed categories: Decayed,Missing,Treated,Pulpitis,Abscess,Fracture,Periodontitis,Attrition,Abrasion,Root Stump,Impacted,Mobility,Recession,Pocket,Normal. '
      'If creating a patient, fill known patient fields and include relevant complaint/history in patient fields. '
      'If request implies chart/diagnosis changes for teeth, include them in changes. '
      'Use empty strings for unknown patient fields and [] for no changes.\nJSON:',
      maxTokens: 768,
    );
    final json = _sanitizeJson(raw);
    json.putIfAbsent('action', () => 'diagnose');
    json.putIfAbsent('reply', () => raw.trim());
    json.putIfAbsent('patient', () => <String, dynamic>{});
    json.putIfAbsent('changes', () => <dynamic>[]);
    return json;
  }

  Map<String, dynamic> _sanitizeJson(String rawText) {
    try {
      var cleanText =
          rawText.replaceAll('```json', '').replaceAll('```', '').trim();
      final startIndex = cleanText.indexOf('{');
      final endIndex = cleanText.lastIndexOf('}');
      if (startIndex != -1 && endIndex != -1 && endIndex >= startIndex) {
        cleanText = cleanText.substring(startIndex, endIndex + 1);
      }
      final decoded = jsonDecode(cleanText);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'error': 'AI extraction failed', 'raw': rawText};
    } catch (_) {
      return {'error': 'AI extraction failed', 'raw': rawText};
    }
  }

  Future<void> disposeModel() async {
    await _model?.close();
    _model = null;
    _modelPath = null;
  }

  Future<void> dispose() async => disposeModel();
}
