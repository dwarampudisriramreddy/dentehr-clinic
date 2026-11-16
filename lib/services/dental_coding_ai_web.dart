import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

@JS('dentalWebAiInit')
external JSPromise<JSAny?> _dentalWebAiInit(JSString modelId, JSFunction? onProgress);

@JS('dentalWebAiGenerate')
external JSPromise<JSString> _dentalWebAiGenerate(JSString prompt, JSNumber maxTokens);

@JS('dentalWebAiReady')
external bool _dentalWebAiReady();

@JS('dentalWebAiModelName')
external JSString _dentalWebAiModelName();

class DentalCodingAI {
  bool _ready = false;
  bool _initializing = false;
  String _modelName = 'WebLLM (WebGPU)';
  final List<String> debugLogs = [];
  String debugStatus = '';

  bool get isReady => _ready || _dentalWebAiReadySafe();
  String? get modelPath => _ready ? 'webllm' : null;
  String? get modelName => _modelName;
  bool get requiresModelFile => false;

  bool _dentalWebAiReadySafe() {
    try {
      return _dentalWebAiReady();
    } catch (_) {
      return false;
    }
  }

  void _log(String msg, [void Function(String)? onLog]) {
    final line = '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg';
    debugLogs.add(line);
    debugStatus = msg;
    onLog?.call(line);
  }

  Future<void> initModel({
    String? modelPath,
    void Function(String)? onLog,
  }) async {
    if (isReady) return;
    if (_initializing) {
      _log('Initialization already in progress...', onLog);
      while (_initializing) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (!isReady) throw StateError(debugStatus.isNotEmpty ? debugStatus : 'Web AI initialization failed');
      return;
    }
    _initializing = true;
    debugLogs.clear();
    debugStatus = '';
    try {
      final modelId = (modelPath == null || modelPath.isEmpty)
          ? 'Llama-3.2-1B-Instruct-q4f16_1-MLC'
          : modelPath;
      _modelName = modelId;
      _log('Initializing Web AI (WebLLM/WebGPU): $modelId', onLog);
      _log('First run downloads and caches model in browser (can take several minutes).', onLog);

      void handleProg(JSAny? report) {
        try {
          String text = '';
          if (report != null) {
            text = (report as JSString?)?.toDart ?? report.dartify()?.toString() ?? report.toString();
          }
          text = text.trim();
          if (text.isNotEmpty && text != 'null' && text != '[object Object]') {
            _log(text, onLog);
          }
        } catch (_) {}
      }

      JSFunction? progressJs;
      try {
        progressJs = handleProg.toJS;
      } catch (_) {
        progressJs = null;
      }

      final result = await _dentalWebAiInit(modelId.toJS, progressJs).toDart;
      _ready = true;
      try { _modelName = _dentalWebAiModelName().toDart; } catch (_) {}
      String resText = 'ready';
      try { resText = result?.dartify()?.toString() ?? 'ready'; } catch (_) {}
      _log('Web AI ready: $resText', onLog);
    } catch (e) {
      _ready = false;
      final msg = e.toString().replaceFirst('Exception: ', '').replaceFirst('Error: ', '');
      _log('ERROR: $msg', onLog);
      _log('If stuck: ensure WebGPU is enabled, check browser console, and allow model download.', onLog);
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  Future<String> generate(String prompt, {int maxTokens = 512}) async {
    if (!isReady) {
      throw StateError('Web AI not initialized. Tap AI to initialize WebGPU model.');
    }
    final res = await _dentalWebAiGenerate(prompt.toJS, maxTokens.toJS).toDart;
    return res.toDart.trim();
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

  Future<Map<String, dynamic>> interpretAgentPrompt(String prompt) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final nowStr = '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
    final raw = await generate(
      'You are an agentic dental clinic assistant. Current datetime: $nowStr.\n'
      'Convert the user request into an action plan.\n'
      'User request: "$prompt"\n'
      'Return ONLY raw JSON, no markdown. Schema:\n'
      '{"action":"create_patient|update_patient|delete_patient|odontogram|query_patients|diagnose","reply":"short confirmation/diagnosis/answer",'
      '"query":{"keyword":"Restoration","match":"treatment_plan|diagnosis|any"},'
      '"patients":[{"patient":{"first_name":"","last_name":"","phone":"","age":"","sex":"","chief_complaint":"","medical_history":"","diagnosis":"","appointment":"","clinic":""},'
      '"changes":[{"tooth":"31","category":"Pulpitis"}]}]}\n'
      'Rules: use FDI tooth numbers 11-18,21-28,31-38,41-48. '
      'Allowed categories: Decayed,Missing,Treated,Pulpitis,Abscess,Fracture,Periodontitis,Attrition,Abrasion,Root Stump,Impacted,Mobility,Recession,Pocket,Normal. '
      'If the user asks a question about EXISTING patients (e.g. "how many patients need restorations", "who has implants", "count patients with caries"), set action to "query_patients", set query.keyword to the treatment/diagnosis term (e.g. "Restoration", "Implant", "Caries"), set query.match to "treatment_plan" or "diagnosis" (or "any"), and set "patients":[]. '
      'If the user says "restorations", use keyword "Restoration"; "root canal" use "Root Canal"; "extraction" use "Extraction"; "crown/bridge" use "FPD". '
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
    _ready = false;
  }

  Future<void> dispose() async => disposeModel();
}
