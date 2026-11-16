import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'appointments_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'odontogram/odontogram.dart';
import 'services/dental_coding_ai.dart';
import 'treatment_screen.dart';
import 'visit_screen.dart';
import 'visits_screen.dart';

const String supabaseUrl = 'https://jsteftqsjcjzcoqbmukg.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpzdGVmdHFzamNqemNvcWJtdWtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1MDgyMDEsImV4cCI6MjEwOTA4NDIwMX0.NNxgOgQHkrCb-X9kp6MuQVDo7xhr08DZA8v4F4nBuKA';

const Color kTeal = Color(0xFF0D9488);
const Color kNavy = Color(0xFF1E3A5F);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const DentehrClinicApp());
}

class DentehrClinicApp extends StatelessWidget {
  const DentehrClinicApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Dentehr Clinic',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: kNavy),
        ),
        home: const ClinicShell(),
        debugShowCheckedModeBanner: false,
      );
}

const _destinations = [
  ('Dashboard', Icons.dashboard_outlined),
  ('Patients', Icons.people_outline),
  ('Appointments', Icons.calendar_month_outlined),
  ('Visits', Icons.receipt_long_outlined),
  ('Treatment', Icons.medical_services_outlined),
];

class ClinicShell extends StatefulWidget {
  const ClinicShell({super.key});
  @override
  State<ClinicShell> createState() => _ClinicShellState();
}

class _ClinicShellState extends State<ClinicShell> {
  int _index = 0;
  final DentalCodingAI _ai = DentalCodingAI();
  bool _aiLoading = false;
  String _aiStatus = '';

  @override
  void dispose() {
    _ai.dispose();
    super.dispose();
  }

  String _normalizeTooth(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    final m = RegExp(r'(1[1-8]|2[1-8]|3[1-8]|4[1-8])').firstMatch(s);
    return m?.group(1) ?? s;
  }

  String _normalizeCategory(dynamic raw) {
    final s = (raw?.toString() ?? '').trim().toLowerCase().replaceAll('_', ' ');
    const map = {
      'decayed': 'Decayed', 'caries': 'Decayed', 'cavity': 'Decayed', 'dental caries': 'Decayed',
      'missing': 'Missing', 'treated': 'Treated', 'filled': 'Treated',
      'restored': 'Treated', 'restoration': 'Treated', 'pulpitis': 'Pulpitis',
      'abscess': 'Abscess', 'fracture': 'Fracture', 'fractured': 'Fracture',
      'periodontitis': 'Periodontitis', 'attrition': 'Attrition',
      'abrasion': 'Abrasion', 'root stump': 'Root Stump',
      'impacted': 'Impacted', 'mobility': 'Mobility',
      'recession': 'Recession', 'pocket': 'Pocket', 'normal': 'Normal',
      'healthy': 'Normal',
    };
    return map[s] ?? (s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}');
  }

  String _normalizeAppointment(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    final now = DateTime.now();
    DateTime? dt;
    if (lower == 'now' || lower.contains('right now')) {
      dt = now;
    } else if (RegExp(r'\b5\s*(min|mins|minute|minutes)\b').hasMatch(lower) || lower.contains('in 5')) {
      dt = now.add(const Duration(minutes: 5));
    } else if (lower.contains('tomorrow')) {
      dt = now.add(const Duration(days: 1));
    }
    if (dt != null) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    }
    return s;
  }

  Future<void> _ensureAiModel() async {
    if (_ai.isReady) return;
    if (_ai.requiresModelFile) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Pick AI model file (.litertlm)',
      );
      if (result == null || result.files.single.path == null) {
        throw Exception('No model file selected');
      }
      final path = result.files.single.path!;
      await _ai.initModel(
        modelPath: path,
        onLog: (msg) {
          if (mounted) setState(() => _aiStatus = msg);
        },
      );
    } else {
      await _ai.initModel(
        onLog: (msg) {
          if (mounted) setState(() => _aiStatus = msg);
        },
      );
    }
  }

  String _keywordFromPrompt(String prompt) {
    final p = prompt.toLowerCase();
    const candidates = <String, List<String>>{
      'Restoration': ['restor', 'filling', 'filled', 'composite'],
      'Root Canal': ['root canal', 'rct', 'endodontic'],
      'Extraction': ['extraction', 'extract', 'remove tooth'],
      'Implant': ['implant'],
      'FPD': ['fpd', 'crown', 'bridge'],
      'Caries': ['caries', 'cavity', 'cavities', 'decay', 'decayed'],
    };
    for (final entry in candidates.entries) {
      if (entry.value.any((w) => p.contains(w))) return entry.key;
    }
    return '';
  }

  List<String> _queryVariants(String keyword) {
    final base = keyword.toLowerCase().trim();
    if (base.isEmpty) return const [];
    final variants = <String>{base};
    if (base.endsWith('s')) variants.add(base.substring(0, base.length - 1));
    const synonyms = <String, List<String>>{
      'restoration': ['restor', 'restoration', 'restored', 'restore', 'filling', 'filled', 'composite'],
      'restor': ['restor', 'restoration', 'restored', 'restore', 'filling', 'filled', 'composite'],
      'root canal': ['root canal', 'rct', 'endodontic'],
      'extraction': ['extraction', 'extract'],
      'implant': ['implant'],
      'fpd': ['fpd', 'crown', 'bridge'],
      'caries': ['caries', 'decay', 'decayed', 'cavity', 'cavities'],
    };
    final normalized = base.endsWith('s') ? base.substring(0, base.length - 1) : base;
    synonyms.forEach((key, values) {
      if (normalized == key || normalized.contains(key) || key.contains(normalized)) {
        variants.addAll(values);
      }
    });
    return variants.toList();
  }

  ({String type, String category}) _resolveQueryCategory(String keyword) {
    final k = keyword.toLowerCase();
    if (k.contains('restor') || k.contains('fill') || k.contains('composite')) {
      return (type: 'treatment', category: 'Restoration');
    }
    if (k.contains('root') || k.contains('rct') || k.contains('endodont')) {
      return (type: 'treatment', category: 'Root Canal');
    }
    if (k.contains('extract')) return (type: 'treatment', category: 'Extraction');
    if (k.contains('implant')) return (type: 'treatment', category: 'Implant');
    if (k.contains('fpd') || k.contains('crown') || k.contains('bridge')) {
      return (type: 'treatment', category: 'FPD');
    }
    if (k.contains('caries') || k.contains('decay') || k.contains('cavit')) {
      return (type: 'diagnosis', category: 'Decayed');
    }
    if (k.contains('missing')) return (type: 'diagnosis', category: 'Missing');
    if (k.contains('treated')) return (type: 'diagnosis', category: 'Treated');
    return (type: 'text', category: keyword);
  }

  String _teethFromPlanText(String planText, String category) {
    final re = RegExp(RegExp.escape(category) + r'\s*:\s*([0-9][0-9,\s]*)', caseSensitive: false);
    final m = re.firstMatch(planText);
    return m?.group(1)?.trim().replaceAll(RegExp(r'\s*,\s*$'), '') ?? '';
  }

  String _teethFor(String keyword, Map<String, dynamic> row) {
    final resolved = _resolveQueryCategory(keyword);
    final odo = OdontogramModel.fromPatientRecord(row);
    String teeth = '';
    if (resolved.type == 'treatment') {
      teeth = (odo.treatmentTeethMap[resolved.category] ?? const <String>[]).join(', ');
    } else if (resolved.type == 'diagnosis') {
      teeth = odo.getTeethStringForCategory(resolved.category);
    }
    if (teeth.isEmpty) {
      teeth = _teethFromPlanText(
        OdontogramModel.cleanDisplayText(row['treatment_plan']?.toString()),
        resolved.category,
      );
    }
    return teeth;
  }

  Future<void> _runPatientQuery(
    String prompt,
    Map<String, dynamic> result,
    String reply,
  ) async {
    final qmap = result['query'] is Map
        ? Map<String, dynamic>.from(result['query'] as Map)
        : <String, dynamic>{};
    var keyword = (qmap['keyword'] ?? '').toString().trim();
    final match = (qmap['match'] ?? 'any').toString().trim().toLowerCase();
    if (keyword.isEmpty) keyword = _keywordFromPrompt(prompt);

    final named = (qmap['patient_name'] ?? '').toString().trim();
    final promptName = _nameFromPrompt(prompt);
    final nameFilter = named.isNotEmpty ? named : promptName;
    if (nameFilter.isNotEmpty && keyword.isEmpty) {
      await _runPatientLookup(nameFilter, reply);
      return;
    }

    final variants = _queryVariants(keyword);
    final rows = nameFilter.isNotEmpty
        ? await _findPatientsByName(nameFilter)
        : await Supabase.instance.client
            .from('patients')
            .select('phone, first_name, last_name, diagnosis, treatment_plan');
    final matches = <String>[];
    for (final row in rows) {
      final plan = (row['treatment_plan'] ?? '').toString().toLowerCase();
      final diag = (row['diagnosis'] ?? '').toString().toLowerCase();
      final haystack = match == 'treatment_plan'
          ? plan
          : match == 'diagnosis'
              ? diag
              : '$plan $diag';
      final teeth = keyword.isEmpty ? '' : _teethFor(keyword, row);
      final textHit = variants.isEmpty
          ? haystack.trim().isNotEmpty
          : variants.any((v) => v.isNotEmpty && haystack.contains(v));
      if (teeth.isEmpty && !textHit) continue;
      final name = [
        row['first_name']?.toString() ?? '',
        row['last_name']?.toString() ?? '',
      ].where((e) => e.trim().isNotEmpty).join(' ').trim();
      final display = name.isEmpty ? (row['phone']?.toString() ?? 'Unknown') : name;
      matches.add(teeth.isEmpty ? display : '$display — $keyword: $teeth');
    }
    final label = keyword.isEmpty ? 'patients' : keyword;
    final summary = '${matches.length} patient(s) with $label';
    final shown = matches.take(40).toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Patient query'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reply.isEmpty ? summary : '$reply\n\n$summary'),
                const SizedBox(height: 12),
                if (matches.isEmpty)
                  const Text('No matching patients.', style: TextStyle(color: Colors.grey))
                else
                  ...shown.map((name) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text('• $name', style: const TextStyle(fontSize: 13)),
                      )),
                if (matches.length > shown.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('+${matches.length - shown.length} more',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  String _nameFromPrompt(String prompt) {
    final re = RegExp(
      r'(?:findings|details|detail|records?|information|info|chart|history|treatment plan|treatment|diagnosis|appointment|status)\s+(?:of|for|in|about)\s+([A-Za-z][A-Za-z .\x27-]{0,40})',
      caseSensitive: false,
    );
    RegExpMatch? m = re.firstMatch(prompt);
    if (m == null) {
      final re2 = RegExp(
        r'(?:show|tell me about|what about|lookup|look up|get|open)\s+(?:the\s+)?([A-Za-z][A-Za-z .\x27-]{0,40})',
        caseSensitive: false,
      );
      m = re2.firstMatch(prompt);
    }
    if (m == null) return '';
    var candidate = m.group(1)!.trim();
    candidate = candidate
        .replaceAll(RegExp(
          r'\b(findings|details|detail|records?|treatment|plan|diagnosis|appointment|please|now)\b.*$',
          caseSensitive: false,
        ), '')
        .replaceAll(RegExp(r'[?.!,]+\s*$'), '')
        .trim();
    final tokens = candidate.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty || tokens.length > 3) return '';
    return candidate;
  }

  Future<List<Map<String, dynamic>>> _findPatientsByName(String name) async {
    final tokens = name.toLowerCase().trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return [];
    List<Map<String, dynamic>> rows = [];
    try {
      final ors = <String>[];
      for (final t in tokens) {
        final esc = t.replaceAll('%', '').replaceAll(',', '').replaceAll('*', '');
        if (esc.isEmpty) continue;
        ors.add('first_name.ilike.%$esc%');
        ors.add('last_name.ilike.%$esc%');
      }
      if (ors.isNotEmpty) {
        final res = await Supabase.instance.client.from('patients').select().or(ors.join(','));
        rows = List<Map<String, dynamic>>.from(res);
      }
    } catch (_) {
      rows = [];
    }
    if (rows.isEmpty) {
      try {
        final res = await Supabase.instance.client.from('patients').select();
        rows = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        return [];
      }
    }
    return rows.where((row) {
      final full = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.toLowerCase();
      return tokens.every((t) => full.contains(t));
    }).toList();
  }

  Future<void> _runPatientLookup(String name, String reply) async {
    final rows = await _findPatientsByName(name);
    if (!mounted) return;
    if (rows.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Patient: $name'),
          content: Text('No patient found matching "$name".'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
      return;
    }
    final blocks = <String>[];
    for (final row in rows.take(10)) {
      final fullName = [
        row['first_name']?.toString() ?? '',
        row['last_name']?.toString() ?? '',
      ].where((e) => e.trim().isNotEmpty).join(' ').trim();
      final phone = (row['phone'] ?? '').toString();
      final appt = (row['appointment'] ?? '').toString();
      final odo = OdontogramModel.fromPatientRecord(row);
      final findings = odo.toDiagnosisSummaryString();
      final treatment = odo.toTreatmentPlanSummaryString();
      final diagText = OdontogramModel.cleanDisplayText(row['diagnosis']?.toString());
      final planText = OdontogramModel.cleanDisplayText(row['treatment_plan']?.toString());
      final findingDisplay = (diagText.isNotEmpty && diagText != 'Oral cavity clinically normal.')
          ? diagText
          : findings;
      final planDisplay = planText.isNotEmpty ? planText : treatment;
      blocks.add([
        fullName.isEmpty ? (phone.isEmpty ? 'Unknown patient' : phone) : fullName,
        if (phone.isNotEmpty) 'Phone: $phone',
        if (appt.isNotEmpty) 'Appointment: $appt',
        'Findings: ${findingDisplay.isEmpty ? 'None recorded' : findingDisplay}',
        'Treatment plan: ${planDisplay.isEmpty ? 'None recorded' : planDisplay}',
      ].join('\n'));
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Patient: $name'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reply.isNotEmpty && rows.length == 1) ...[
                  Text(reply),
                  const Divider(height: 20),
                ],
                ...blocks.map((b) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(b, style: const TextStyle(fontSize: 13, height: 1.4)),
                    )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _runGlobalAi() async {
    final promptController = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI'),
        content: TextField(
          controller: promptController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, promptController.text.trim()),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    if (prompt == null || prompt.isEmpty) return;

    setState(() {
      _aiLoading = true;
      _aiStatus = 'Starting...';
    });
    try {
      if (!_ai.isReady) {
        if (mounted) setState(() => _aiStatus = _ai.requiresModelFile ? 'Pick a model file...' : 'Initializing Web AI (first run may download model)...');
        await _ensureAiModel();
      }
      if (mounted) setState(() => _aiStatus = 'Thinking...');
      final result = await _ai.interpretAgentPrompt(prompt);
      var action = (result['action'] ?? 'diagnose').toString();
      final reply = (result['reply'] ?? '').toString();
      final patientsRaw = result['patients'] is List ? result['patients'] as List : const [];

      final promptLower = prompt.toLowerCase();
      final promptName = _nameFromPrompt(prompt);
      final fallbackKeyword = _keywordFromPrompt(prompt);
      final hasMutation = RegExp(
        r'\b(create|add|update|change|set|mark|delete|remove|diagnose|record|save|schedule|book)\b',
      ).hasMatch(promptLower);
      final looksLikeQuery = RegExp(
        r'\b(how many|how much|which|what are|what is|list|who|count|are there|do we have|show me|tell me|give me|findings|teeth)\b',
      ).hasMatch(promptLower);
      if (action == 'diagnose' && !hasMutation) {
        if (promptName.isNotEmpty) {
          action = 'patient_lookup';
        } else if (fallbackKeyword.isNotEmpty && looksLikeQuery) {
          action = 'query_patients';
        }
      }

      if (action == 'delete_patient') {
        var deletedCount = 0;
        var failedCount = 0;
        for (final entry in patientsRaw) {
          if (entry is! Map) continue;
          final pmap = entry['patient'] is Map
              ? Map<String, dynamic>.from(entry['patient'] as Map)
              : <String, dynamic>{};
          final phone = (pmap['phone'] ?? '').toString().trim();
          final first = (pmap['first_name'] ?? '').toString().trim();
          final last = (pmap['last_name'] ?? '').toString().trim();
          try {
            if (phone.isNotEmpty) {
              final res = await Supabase.instance.client.from('patients').delete().eq('phone', phone).select();
              if (res.isNotEmpty) {
                deletedCount += res.length;
              } else {
                failedCount++;
              }
            } else if (first.isNotEmpty || last.isNotEmpty) {
              var q = Supabase.instance.client.from('patients').delete();
              if (first.isNotEmpty) q = q.ilike('first_name', first);
              if (last.isNotEmpty) q = q.ilike('last_name', last);
              final res = await q.select();
              if (res.isNotEmpty) {
                deletedCount += res.length;
              } else {
                failedCount++;
              }
            } else {
              failedCount++;
            }
          } catch (_) {
            failedCount++;
          }
        }
        if (!mounted) return;
        var msg = reply.isEmpty ? 'Delete requested' : reply;
        if (deletedCount > 0) msg = '$msg (deleted $deletedCount)';
        if (failedCount > 0) msg = '$msg (failed $failedCount)';
        if (deletedCount == 0 && failedCount == 0) msg = '$msg (nothing to delete)';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        if (deletedCount > 0) setState(() => _index = 1);
      } else if (action == 'query_patients') {
        await _runPatientQuery(prompt, result, reply);
      } else if (action == 'patient_lookup') {
        var name = result['query'] is Map
            ? (result['query'] as Map)['patient_name']?.toString().trim() ?? ''
            : '';
        if (name.isEmpty) name = promptName;
        if (name.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Which patient? Include the patient name in your question.')),
          );
        } else {
          await _runPatientLookup(name, reply);
        }
      } else {
        var savedCount = 0;
        var failedSaves = 0;
        for (final entry in patientsRaw) {
          if (entry is! Map) continue;
          final pmap = entry['patient'] is Map
              ? Map<String, dynamic>.from(entry['patient'] as Map)
              : <String, dynamic>{};
          final changes = entry['changes'] is List ? entry['changes'] as List : const [];

          final first = (pmap['first_name'] ?? '').toString().trim();
          final last = (pmap['last_name'] ?? '').toString().trim();
          final aiPhone = (pmap['phone'] ?? '').toString().trim();
          final age = int.tryParse((pmap['age'] ?? '').toString().trim());
          final sex = (pmap['sex'] ?? '').toString().trim();
          final clinic = (pmap['clinic'] ?? 'Dentehr Clinic').toString().trim().isEmpty
              ? 'Dentehr Clinic'
              : (pmap['clinic'] ?? 'Dentehr Clinic').toString().trim();
          final complaint = (pmap['chief_complaint'] ?? '').toString().trim();
          final history = (pmap['medical_history'] ?? '').toString().trim();
          final diagField = (pmap['diagnosis'] ?? '').toString().trim();

          // Resolve existing patient by phone or name so updates/chart edits
          // modify the existing record instead of creating a duplicate.
          Map<String, dynamic>? existingRow;
          try {
            if (aiPhone.isNotEmpty) {
              final res = await Supabase.instance.client
                  .from('patients')
                  .select()
                  .eq('phone', aiPhone)
                  .limit(1);
              if (res.isNotEmpty) existingRow = Map<String, dynamic>.from(res.first);
            }
            if (existingRow == null && (first.isNotEmpty || last.isNotEmpty)) {
              var q = Supabase.instance.client.from('patients').select();
              if (first.isNotEmpty) q = q.ilike('first_name', first);
              if (last.isNotEmpty) q = q.ilike('last_name', last);
              final res = await q.limit(1);
              if (res.isNotEmpty) existingRow = Map<String, dynamic>.from(res.first);
            }
          } catch (_) {}

          final odo = existingRow != null
              ? OdontogramModel.fromPatientRecord(existingRow)
              : OdontogramModel();
          for (final c in changes) {
            if (c is! Map) continue;
            final tooth = _normalizeTooth(c['tooth']);
            final cat = _normalizeCategory(c['category']);
            if (RegExp(r'^(1[1-8]|2[1-8]|3[1-8]|4[1-8])$').hasMatch(tooth) &&
                cat.isNotEmpty && cat != 'Normal') {
              final existingTeeth = odo.getTeethStringForCategory(cat);
              final merged = existingTeeth.isEmpty ? tooth : '$existingTeeth, $tooth';
              odo.setTeethForCategory(cat, merged);
            }
          }

          final odoDiag = odo.toDiagnosisSummaryString();
          final hasData = first.isNotEmpty || aiPhone.isNotEmpty || complaint.isNotEmpty ||
              history.isNotEmpty || diagField.isNotEmpty || changes.isNotEmpty;
          final shouldSave = action != 'diagnose' && hasData &&
              (action == 'create_patient' || action == 'update_patient' || action == 'odontogram' ||
               first.isNotEmpty || aiPhone.isNotEmpty || changes.isNotEmpty);
          if (!shouldSave) continue;

          final newDiagnosis = [
            if (complaint.isNotEmpty) 'Complaint: $complaint',
            if (history.isNotEmpty) 'History: $history',
            if (diagField.isNotEmpty) diagField,
            if (changes.isNotEmpty && odoDiag.isNotEmpty && odoDiag != 'Oral cavity clinically normal.') odoDiag,
          ].where((e) => e.trim().isNotEmpty).join('\n');
          final existingDiagnosis = existingRow != null
              ? OdontogramModel.cleanDisplayText(existingRow['diagnosis']?.toString())
              : '';
          final diagnosis = newDiagnosis.isNotEmpty
              ? newDiagnosis
              : (existingDiagnosis.isNotEmpty ? existingDiagnosis : reply);

          var phone = aiPhone;
          if (phone.isEmpty && existingRow != null) {
            phone = (existingRow['phone'] ?? '').toString().trim();
          }
          if (phone.isEmpty) phone = 'AI-${DateTime.now().millisecondsSinceEpoch}-$savedCount';

          final apptRaw = (pmap['appointment'] ?? '').toString().trim();
          final existingAppt = existingRow != null ? (existingRow['appointment'] ?? '').toString().trim() : '';
          final appointment = apptRaw.isNotEmpty
              ? _normalizeAppointment(apptRaw)
              : (existingAppt.isNotEmpty ? existingAppt : 'AI Created');

          final existingPlan = existingRow != null ? (existingRow['treatment_plan']?.toString() ?? '') : '';
          final treatmentPlanValue = (changes.isNotEmpty || existingRow == null || existingPlan.isEmpty)
              ? odo.embedInString(odo.toTreatmentPlanSummaryString())
              : existingPlan;

          final existingFirst = existingRow != null ? (existingRow['first_name']?.toString().trim() ?? '') : '';
          final existingLast = existingRow != null ? (existingRow['last_name']?.toString().trim() ?? '') : '';
          final finalSex = sex.isNotEmpty ? sex : (existingRow != null ? (existingRow['sex']?.toString().trim() ?? '') : '');
          final existingAge = existingRow != null ? int.tryParse(existingRow['age']?.toString() ?? '') : null;
          final finalAge = age ?? existingAge;

          try {
            await Supabase.instance.client.from('patients').upsert({
              'phone': phone,
              'first_name': first.isNotEmpty ? first : (existingFirst.isNotEmpty ? existingFirst : 'AI'),
              'last_name': last.isNotEmpty ? last : existingLast,
              'age': ?finalAge,
              if (finalSex.isNotEmpty) 'sex': finalSex,
              'diagnosis': diagnosis.isEmpty ? reply : diagnosis,
              'treatment_plan': treatmentPlanValue,
              'appointment': appointment,
              'clinic': clinic,
            }, onConflict: 'phone');
            savedCount++;
          } catch (_) {
            failedSaves++;
          }
        }

        if (!mounted) return;
        if (action == 'diagnose' && savedCount == 0 && reply.isNotEmpty) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('AI diagnosis'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Text(reply, style: const TextStyle(fontSize: 14, height: 1.4)),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ],
            ),
          );
          return;
        }
        var msg = reply.isEmpty ? 'AI action completed' : reply;
        if (savedCount > 0) msg = '$msg (saved $savedCount)';
        if (failedSaves > 0) msg = '$msg (could not save $failedSaves - no internet/server)';
        if (savedCount == 0 && failedSaves == 0 && patientsRaw.isNotEmpty && action != 'diagnose') {
          final hasAnyData = patientsRaw.any((e) => e is Map && ((e['changes'] is List && (e['changes'] as List).isNotEmpty) ||
              (e['patient'] is Map && ((e['patient'] as Map)['first_name']?.toString().trim().isNotEmpty == true ||
               (e['patient'] as Map)['phone']?.toString().trim().isNotEmpty == true))));
          if (hasAnyData) msg = '$msg (not saved)';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        if (savedCount > 0) setState(() => _index = 1);
      }
    } catch (e) {
      if (mounted) {
        final em = e.toString();
        final friendly = em.contains('Failed host lookup') || em.contains('SocketException') || em.contains('ClientException')
            ? 'No internet connection to clinic server.'
            : 'AI error: $em';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() { _aiLoading = false; _aiStatus = ''; });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget getBody() {
      switch (_index) {
        case 0:
          return DashboardScreen(onNavigateToPatients: () => setState(() => _index = 1));
        case 1:
          return const ClinicPatientsScreen();
        case 2:
          return const AppointmentsScreen();
        case 3:
          return const VisitsScreen();
        case 4:
          return const TreatmentScreen();
        default:
          return DashboardScreen(onNavigateToPatients: () => setState(() => _index = 1));
      }
    }

    final fab = FloatingActionButton.extended(
      onPressed: _aiLoading ? null : _runGlobalAi,
      icon: _aiLoading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.auto_awesome),
      label: Text(_aiLoading && _aiStatus.isNotEmpty
          ? (_aiStatus.length > 28 ? 'AI initializing...' : _aiStatus)
          : 'AI'),
      backgroundColor: kNavy,
      foregroundColor: Colors.white,
    );

    final isWide = MediaQuery.of(context).size.width >= 900;
    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: _destinations
                  .map((d) => NavigationRailDestination(icon: Icon(d.$2), label: Text(d.$1)))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: getBody()),
          ],
        ),
        floatingActionButton: fab,
      );
    }

    return Scaffold(
      body: getBody(),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w600 : FontWeight.w500);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: _destinations
              .map((d) => NavigationDestination(icon: Icon(d.$2), label: d.$1))
              .toList(),
        ),
      ),
      floatingActionButton: fab,
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final VoidCallback onNavigateToPatients;
  const DashboardScreen({super.key, required this.onNavigateToPatients});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  void _startVisit() {
    Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PatientVisitScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clinic Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _startVisit,
                  icon: const Icon(Icons.medical_services_outlined),
                  label: const Text('Start Patient Visit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onNavigateToPatients,
                  icon: const Icon(Icons.grid_on_outlined),
                  label: const Text('View Patients & Charts'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Recent Patient Dental Charts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Expanded(child: ClinicPatientsScreen(isEmbedded: true)),
          ],
        ),
      ),
    );
  }
}

class ClinicPatientsScreen extends StatefulWidget {
  final bool isEmbedded;
  const ClinicPatientsScreen({super.key, this.isEmbedded = false});
  @override
  State<ClinicPatientsScreen> createState() => _ClinicPatientsScreenState();
}

class _ClinicPatientsScreenState extends State<ClinicPatientsScreen> {
  List<Map<String, dynamic>> _patients = [];
  bool _loading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchPatients();
  }

  Future<void> _fetchPatients() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('patients')
          .select()
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _patients = List<Map<String, dynamic>>.from(res));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openPatientDetails(Map<String, dynamic> row) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PatientDentalChartFullScreenPage(patientRow: row, onUpdated: _fetchPatients),
      ),
    );
  }

  void _startVisit([Map<String, dynamic>? patient]) {
    Navigator.push(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => PatientVisitScreen(patient: patient)),
    ).then((_) => _fetchPatients());
  }

  Future<void> _deletePatient(Map<String, dynamic> p) async {
    final phone = p['phone']?.toString().trim() ?? '';
    final name = [
      p['first_name']?.toString().trim() ?? '',
      p['last_name']?.toString().trim() ?? '',
    ].where((e) => e.isNotEmpty).join(' ').trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete case history?'),
        content: Text('Delete ${name.isEmpty ? 'this patient' : name}${phone.isEmpty ? '' : ' ($phone)'}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete: patient has no phone/id'), backgroundColor: Colors.red),
      );
      return;
    }
    try {
      final res = await Supabase.instance.client.from('patients').delete().eq('phone', phone).select();
      if (!mounted) return;
      if (res.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Case history deleted')));
        _fetchPatients();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not deleted (no matching record or no permission)'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildPatientMetaChip(IconData icon, String label, {Color color = kNavy}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _patients.where((p) {
      final phone = p['phone']?.toString().toLowerCase() ?? '';
      final firstName = p['first_name']?.toString().toLowerCase() ?? '';
      final lastName = p['last_name']?.toString().toLowerCase() ?? '';
      final diag = p['diagnosis']?.toString().toLowerCase() ?? '';
      final q = _searchQuery.toLowerCase();
      return phone.contains(q) || firstName.contains(q) || lastName.contains(q) || diag.contains(q);
    }).toList();

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : filtered.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_off_outlined, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('No patient records found'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _startVisit(),
                      icon: const Icon(Icons.medical_services_outlined),
                      label: const Text('Start Patient Visit'),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _fetchPatients,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final p = filtered[i];
                    final phone = p['phone']?.toString().trim() ?? '';
                    final firstName = p['first_name']?.toString().trim() ?? '';
                    final lastName = p['last_name']?.toString().trim() ?? '';
                    final name = [firstName, lastName].where((part) => part.isNotEmpty).join(' ');
                    final age = p['age']?.toString().trim() ?? '';
                    final sex = p['sex']?.toString().trim() ?? '';
                    final appt = p['appointment']?.toString().trim() ?? '';
                    final diag = OdontogramModel.cleanDisplayText(p['diagnosis'] ?? '');
                    final initials = [
                      if (firstName.isNotEmpty) firstName[0].toUpperCase(),
                      if (lastName.isNotEmpty) lastName[0].toUpperCase(),
                    ].join();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openPatientDetails(p),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFFE0F2FE),
                                    child: initials.isEmpty
                                        ? const Icon(Icons.person, color: kNavy)
                                        : Text(initials, style: const TextStyle(color: kNavy, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name.isEmpty ? 'Unnamed Patient' : name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(Icons.phone_outlined, size: 13, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                phone.isEmpty ? 'No phone number' : phone,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.medical_services_outlined, color: kTeal, size: 20),
                                    tooltip: 'Start new visit',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _startVisit(p),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.picture_as_pdf, color: Colors.indigo, size: 20),
                                    tooltip: 'Export PDF',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      final odontogram = OdontogramModel.fromPatientRecord(p);
                                      OdontogramPdfService.printOrShare(
                                        context: context,
                                        model: odontogram,
                                        phone: phone,
                                        appointment: appt,
                                        clinic: p['clinic']?.toString() ?? '',
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    tooltip: 'Delete case history',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _deletePatient(p),
                                  ),
                                  const Icon(Icons.chevron_right, color: Colors.grey),
                                ],
                              ),
                              if (age.isNotEmpty || sex.isNotEmpty || (appt.isNotEmpty && appt != 'None')) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (age.isNotEmpty) _buildPatientMetaChip(Icons.cake_outlined, 'Age: $age'),
                                    if (sex.isNotEmpty) _buildPatientMetaChip(Icons.person_outline, sex),
                                    if (appt.isNotEmpty && appt != 'None')
                                      _buildPatientMetaChip(Icons.event_outlined, 'Appt: $appt', color: Colors.teal),
                                  ],
                                ),
                              ],
                              if (diag.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(diag, maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );

    if (widget.isEmbedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients & Dental Charts'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchPatients),
          ElevatedButton.icon(
            onPressed: () => _startVisit(),
            icon: const Icon(Icons.medical_services_outlined, size: 16),
            label: const Text('Start Visit'),
            style: ElevatedButton.styleFrom(backgroundColor: kTeal, foregroundColor: Colors.white),
          ),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or diagnosis...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
        ),
      ),
      body: content,
    );
  }
}

class PatientDentalChartFullScreenPage extends StatefulWidget {
  final Map<String, dynamic> patientRow;
  final VoidCallback? onUpdated;
  const PatientDentalChartFullScreenPage({super.key, required this.patientRow, this.onUpdated});
  @override
  State<PatientDentalChartFullScreenPage> createState() => _PatientDentalChartFullScreenPageState();
}

class _PatientDentalChartFullScreenPageState extends State<PatientDentalChartFullScreenPage> {
  late OdontogramModel _odontogram;
  late String _phone;
  late String _appointment;
  late String _clinic;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _odontogram = OdontogramModel.fromPatientRecord(widget.patientRow);
    _phone = widget.patientRow['phone']?.toString() ?? '';
    _appointment = widget.patientRow['appointment']?.toString() ?? '';
    _clinic = widget.patientRow['clinic']?.toString() ?? 'Dentehr Clinic';
  }

  Future<void> _saveChanges() async {
    setState(() => _saving = true);
    try {
      final diagnosisText = _odontogram.toDiagnosisSummaryString();
      final treatmentText = _odontogram.toTreatmentPlanSummaryString();
      await Supabase.instance.client.from('patients').upsert({
        'phone': _phone,
        'diagnosis': diagnosisText,
        'treatment_plan': _odontogram.embedInString(treatmentText),
        'appointment': _appointment,
        'clinic': _clinic,
      }, onConflict: 'phone');
      widget.onUpdated?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dental Chart changes saved successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Patient: $_phone'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.medical_services_outlined),
            tooltip: 'Start visit',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(fullscreenDialog: true, builder: (_) => PatientVisitScreen(patient: widget.patientRow)),
              ).then((_) => widget.onUpdated?.call());
            },
          ),
          ElevatedButton.icon(
            onPressed: () {
              OdontogramPdfService.printOrShare(
                context: context, model: _odontogram, phone: _phone, appointment: _appointment, clinic: _clinic,
              );
            },
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('PDF'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kNavy),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveChanges,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(backgroundColor: kTeal, foregroundColor: Colors.white),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: OdontogramWidget(
          model: _odontogram,
          isReadOnly: false,
          isFullScreen: true,
          patientPhone: _phone,
          appointment: _appointment,
          clinic: _clinic,
          showPdfExportButton: false,
          onChanged: () => setState(() {}),
        ),
      ),
    );
  }
}
