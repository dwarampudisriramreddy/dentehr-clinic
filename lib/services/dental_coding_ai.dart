import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

class DentalCodingAI {
  static bool _initialized = false;

  InferenceModel? _model;
  String? _modelPath;
  final List<String> debugLogs = [];
  String debugStatus = '';

  bool get isReady => _model != null;
  String? get modelPath => _modelPath;
  String? get modelName => _modelPath?.split(RegExp(r'[\\/]')).last;

  void _log(String msg, [void Function(String)? onLog]) {
    final line = '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg';
    debugLogs.add(line);
    debugStatus = msg;
    onLog?.call(line);
  }

  Future<void> initModel({
    required String modelPath,
    void Function(String)? onLog,
  }) async {
    debugLogs.clear();
    debugStatus = '';
    try {
      _log('Selected model: $modelPath', onLog);
      if (!_initialized) {
        _log('Initializing FlutterEdgeAi (LiteRT-LM engine)...', onLog);
        await FlutterEdgeAi.initialize(
          inferenceEngines: const [LiteRtLmEngine()],
        );
        _initialized = true;
        _log('Engine initialized', onLog);
      } else {
        _log('Engine already initialized', onLog);
      }

      if (_model != null) {
        _log('Disposing previous model...', onLog);
        await disposeModel();
      }

      _log('Installing model from file (this may take a while for large models)...', onLog);
      await FlutterEdgeAi.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(modelPath).install();
      _log('Model installed', onLog);

      _log('Activating model (maxTokens=512, backend=gpu)...', onLog);
      _model = await FlutterEdgeAi.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.gpu,
      );
      _modelPath = modelPath;
      _log('Model ready: ${modelName ?? pathName(modelPath)}', onLog);
    } catch (e, st) {
      _log('ERROR: $e', onLog);
      _log('Stack: ${st.toString().split('\n').take(4).join(' | ')}', onLog);
      rethrow;
    }
  }

  static String pathName(String p) => p.split(RegExp(r'[\\/]')).last;

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

  /// Agent mode: interpret a natural-language command that may create/update
  /// one or more patients and modify odontogram findings.
  /// Returns {"action":"create_patient|update_patient|odontogram|diagnose",
  /// "reply":"...", "patients":[{"patient":{...},"changes":[{tooth,category},...]}]}
  Future<Map<String, dynamic>> interpretAgentPrompt(String prompt) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final nowStr = '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
    final raw = await generate(
      'You are an agentic dental clinic assistant. Current datetime: $nowStr.\n'
      'Convert the user request into an action plan.\n'
      'User request: "$prompt"\n'
      'Return ONLY raw JSON, no markdown. Schema:\n'
      '{"action":"create_patient|update_patient|delete_patient|odontogram|diagnose","reply":"short confirmation/diagnosis",'
      '"patients":[{"patient":{"first_name":"","last_name":"","phone":"","age":"","sex":"","chief_complaint":"","medical_history":"","diagnosis":"","appointment":"","clinic":""},'
      '"changes":[{"tooth":"31","category":"Pulpitis"}]}]}\n'
      'Rules: use FDI tooth numbers 11-18,21-28,31-38,41-48. '
      'Allowed categories: Decayed,Missing,Treated,Pulpitis,Abscess,Fracture,Periodontitis,Attrition,Abrasion,Root Stump,Impacted,Mobility,Recession,Pocket,Normal. '
      'If multiple patients are mentioned, return one entry per patient and assign ONLY that patient\'s findings/teeth to their changes. '
      'Do not mix different patients\' findings. '
      'If user asks to delete/remove a patient or case history, set action to "delete_patient" and provide identifying patient fields (first_name/last_name/phone) per entry. '
      'If appointment/timing is mentioned (now, in 5 minutes, tomorrow, specific time), set patient.appointment to a concrete "YYYY-MM-DD HH:mm" value computed from current datetime. '
      'If creating/updating, fill known patient fields. Use empty strings for unknown fields and [] for no changes.\nJSON:',
      maxTokens: 1024,
    );
    final json = _sanitizeJson(raw);
    json.putIfAbsent('action', () => 'diagnose');
    json.putIfAbsent('reply', () => raw.trim());

    // Backward compatibility: normalize single-patient shape to patients[]
    if (json['patients'] is! List) {
      final p = json['patient'] is Map
          ? Map<String, dynamic>.from(json['patient'] as Map)
          : <String, dynamic>{};
      final c = json['changes'] is List ? json['changes'] as List : <dynamic>[];
      json['patients'] = [
        {'patient': p, 'changes': c}
      ];
    }
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
    try {
      await _model?.close();
    } catch (_) {}
    _model = null;
    _modelPath = null;
  }

  Future<void> dispose() async => disposeModel();
}
