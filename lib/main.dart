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
      'decayed': 'Decayed', 'caries': 'Decayed', 'cavity': 'Decayed',
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

  Future<void> _ensureAiModel() async {
    if (_ai.isReady) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['litertlm', 'task', 'bin'],
      dialogTitle: 'Pick AI model file (.litertlm)',
    );
    if (result == null || result.files.single.path == null) {
      throw Exception('No model file selected');
    }
    await _ai.initModel(modelPath: result.files.single.path!);
  }

  Future<void> _runGlobalAiAgent() async {
    final promptController = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI'),
        content: TextField(
          controller: promptController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
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

    setState(() => _aiLoading = true);
    try {
      await _ensureAiModel();
      final result = await _ai.interpretAgentPrompt(prompt);
      final action = (result['action'] ?? 'diagnose').toString();
      final reply = (result['reply'] ?? '').toString();
      final patient = result['patient'] is Map
          ? Map<String, dynamic>.from(result['patient'] as Map)
          : <String, dynamic>{};
      final changes = result['changes'] is List ? result['changes'] as List : const [];

      final odo = OdontogramModel();
      for (final c in changes) {
        if (c is! Map) continue;
        final tooth = _normalizeTooth(c['tooth']);
        final cat = _normalizeCategory(c['category']);
        if (RegExp(r'^(1[1-8]|2[1-8]|3[1-8]|4[1-8])$').hasMatch(tooth) &&
            cat.isNotEmpty && cat != 'Normal') {
          final existing = odo.getTeethStringForCategory(cat);
          final merged = existing.isEmpty ? tooth : '$existing, $tooth';
          odo.setTeethForCategory(cat, merged);
        }
      }
      final first = (patient['first_name'] ?? '').toString().trim();
      final last = (patient['last_name'] ?? '').toString().trim();
      final aiPhone = (patient['phone'] ?? '').toString().trim();
      final age = int.tryParse((patient['age'] ?? '').toString().trim());
      final sex = (patient['sex'] ?? '').toString().trim();
      final clinic = (patient['clinic'] ?? 'Dentehr Clinic').toString().trim().isEmpty
          ? 'Dentehr Clinic'
          : (patient['clinic'] ?? 'Dentehr Clinic').toString().trim();
      final complaint = (patient['chief_complaint'] ?? '').toString().trim();
      final history = (patient['medical_history'] ?? '').toString().trim();
      final diagField = (patient['diagnosis'] ?? '').toString().trim();
      final odoDiag = odo.toDiagnosisSummaryString();
      final hasPatientData = first.isNotEmpty ||
          aiPhone.isNotEmpty ||
          complaint.isNotEmpty ||
          history.isNotEmpty ||
          diagField.isNotEmpty ||
          changes.isNotEmpty;

      if ((action == 'create_patient' || action == 'update_patient') && hasPatientData) {
        final diagnosis = [
          if (complaint.isNotEmpty) 'Complaint: $complaint',
          if (history.isNotEmpty) 'History: $history',
          if (diagField.isNotEmpty) diagField,
          if (odoDiag.isNotEmpty && odoDiag != 'Oral cavity clinically normal.') odoDiag,
        ].where((e) => e.trim().isNotEmpty).join('\n');
        var phone = aiPhone;
        if (phone.isEmpty) phone = 'AI-${DateTime.now().millisecondsSinceEpoch}';
        try {
          await Supabase.instance.client.from('patients').upsert({
            'phone': phone,
            'first_name': first.isEmpty ? 'AI' : first,
            'last_name': last,
            if (age != null) 'age': age,
            if (sex.isNotEmpty) 'sex': sex,
            'diagnosis': diagnosis.isEmpty ? reply : diagnosis,
            'treatment_plan': odo.embedInString(odo.toTreatmentPlanSummaryString()),
            'appointment': (patient['appointment'] ?? 'AI Created').toString(),
            'clinic': clinic,
          }, onConflict: 'phone');
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(reply.isEmpty ? 'AI responded, but could not save to server (no internet).' : '$reply\n(Could not save to server: no internet)')),
          );
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reply.isEmpty ? 'AI action completed' : reply)),
      );
      if (_index == 1 || _index == 0) {
        setState(() {}); // refresh current context; lists refetch on open/manual refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI agent error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
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
      onPressed: _aiLoading ? null : _runGlobalAiAgent,
      icon: _aiLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.auto_awesome),
      label: const Text('AI'),
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
                  .map(
                    (d) => NavigationRailDestination(
                      icon: Icon(d.$2),
                      label: Text(d.$1),
                    ),
                  )
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
            return TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: _destinations
              .map(
                (d) => NavigationDestination(
                  icon: Icon(d.$2),
                  label: d.$1,
                ),
              )
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
  void _addPatient() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PatientVisitScreen(),
      ),
    );
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
                  onPressed: _addPatient,
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
                  label: const Text('View Full Dental Charts'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Recent Patient Dental Charts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
  final DentalCodingAI _ai = DentalCodingAI();
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchPatients();
  }

  @override
  void dispose() {
    _ai.dispose();
    super.dispose();
  }

  Future<void> _fetchPatients() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('patients')
          .select()
          .order('created_at', ascending: false);
      setState(() {
        _patients = List<Map<String, dynamic>>.from(res);
      });
    } catch (_) {
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openPatientDetails(Map<String, dynamic> row) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PatientDentalChartFullScreenPage(
          patientRow: row,
          onUpdated: _fetchPatients,
        ),
      ),
    );
  }

  void _startVisit([Map<String, dynamic>? patient]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PatientVisitScreen(patient: patient),
      ),
    ).then((_) => _fetchPatients());
  }

  void _addNewPatient() => _startVisit();


  String _normalizeTooth(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    final m = RegExp(r'(1[1-8]|2[1-8]|3[1-8]|4[1-8])').firstMatch(s);
    return m?.group(1) ?? s;
  }

  String _normalizeCategory(dynamic raw) {
    final s = (raw?.toString() ?? '').trim().toLowerCase().replaceAll('_', ' ');
    const map = {
      'decayed': 'Decayed', 'caries': 'Decayed', 'cavity': 'Decayed',
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

  Future<void> _ensureAiModel() async {
    if (_ai.isReady) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['litertlm', 'task', 'bin'],
      dialogTitle: 'Pick AI model file (.litertlm)',
    );
    if (result == null || result.files.single.path == null) {
      throw Exception('No model file selected');
    }
    final path = result.files.single.path!;
    await _ai.initModel(modelPath: path);
  }

  Future<void> _runAiAgentPrompt() async {
    final promptController = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI'),
        content: TextField(
          controller: promptController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
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

    setState(() => _aiLoading = true);
    try {
      await _ensureAiModel();
      final result = await _ai.interpretAgentPrompt(prompt);
      final action = (result['action'] ?? 'diagnose').toString();
      final reply = (result['reply'] ?? '').toString();
      final patient = result['patient'] is Map
          ? Map<String, dynamic>.from(result['patient'] as Map)
          : <String, dynamic>{};
      final changes = result['changes'] is List ? result['changes'] as List : const [];

      final odo = OdontogramModel();
      for (final c in changes) {
        if (c is! Map) continue;
        final tooth = _normalizeTooth(c['tooth']);
        final cat = _normalizeCategory(c['category']);
        if (RegExp(r'^(1[1-8]|2[1-8]|3[1-8]|4[1-8])$').hasMatch(tooth) &&
            cat.isNotEmpty && cat != 'Normal') {
          final existing = odo.getTeethStringForCategory(cat);
          final merged = existing.isEmpty ? tooth : '$existing, $tooth';
          odo.setTeethForCategory(cat, merged);
        }
      }
      final first = (patient['first_name'] ?? '').toString().trim();
      final last = (patient['last_name'] ?? '').toString().trim();
      final aiPhone = (patient['phone'] ?? '').toString().trim();
      final ageStr = (patient['age'] ?? '').toString().trim();
      final age = int.tryParse(ageStr);
      final sex = (patient['sex'] ?? '').toString().trim();
      final clinic = (patient['clinic'] ?? _clinicDefault).toString().trim().isEmpty
          ? _clinicDefault
          : (patient['clinic'] ?? _clinicDefault).toString().trim();
      final complaint = (patient['chief_complaint'] ?? '').toString().trim();
      final history = (patient['medical_history'] ?? '').toString().trim();
      final diagField = (patient['diagnosis'] ?? '').toString().trim();
      final odoDiag = odo.toDiagnosisSummaryString();
      final hasPatientData = first.isNotEmpty ||
          aiPhone.isNotEmpty ||
          complaint.isNotEmpty ||
          history.isNotEmpty ||
          diagField.isNotEmpty ||
          changes.isNotEmpty;

      if ((action == 'create_patient' || action == 'update_patient') && hasPatientData) {
        final diagnosis = [
          if (complaint.isNotEmpty) 'Complaint: $complaint',
          if (history.isNotEmpty) 'History: $history',
          if (diagField.isNotEmpty) diagField,
          if (odoDiag.isNotEmpty && odoDiag != 'Oral cavity clinically normal.')
            odoDiag,
        ].where((e) => e.trim().isNotEmpty).join('\n');
        var phone = aiPhone;
        if (phone.isEmpty) phone = 'AI-${DateTime.now().millisecondsSinceEpoch}';
        try {
          await Supabase.instance.client.from('patients').upsert({
            'phone': phone,
            'first_name': first.isEmpty ? 'AI' : first,
            'last_name': last,
            if (age != null) 'age': age,
            if (sex.isNotEmpty) 'sex': sex,
            'diagnosis': diagnosis.isEmpty ? reply : diagnosis,
            'treatment_plan': odo.embedInString(odo.toTreatmentPlanSummaryString()),
            'appointment': (patient['appointment'] ?? 'AI Created').toString(),
            'clinic': clinic,
          }, onConflict: 'phone');
          await _fetchPatients();
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(reply.isEmpty ? 'AI responded, but could not save to server (no internet).' : '$reply\n(Could not save to server: no internet)')),
          );
          return;
        }
      } else if (action == 'odontogram' || action == 'update') {
        // fallback: show reply; odontogram-only without target patient needs context
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reply.isEmpty ? 'AI action completed' : reply)),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final friendly = msg.contains('Failed host lookup') ||
                msg.contains('SocketException') ||
                msg.contains('ClientException')
            ? 'No internet connection to clinic server. AI model can run offline, but creating/updating patients needs network.'
            : 'AI error: $msg';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendly), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  static const String _clinicDefault = 'Dentehr Clinic';

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
      return phone.contains(q) ||
          firstName.contains(q) ||
          lastName.contains(q) ||
          diag.contains(q);
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
                      onPressed: _addNewPatient,
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
                                        : Text(
                                            initials,
                                            style: const TextStyle(color: kNavy, fontWeight: FontWeight.bold),
                                          ),
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
                                Text(
                                  diag,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
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
          IconButton(
            tooltip: 'AI Assistant',
            onPressed: _aiLoading ? null : _runAiAgentPrompt,
            icon: _aiLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
          ),
          ElevatedButton.icon(
            onPressed: _addNewPatient,
            icon: const Icon(Icons.medical_services_outlined, size: 16),
            label: const Text('Start Visit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kTeal,
              foregroundColor: Colors.white,
            ),
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

/// Full screen page for viewing and editing a patient's Dental Chart
class PatientDentalChartFullScreenPage extends StatefulWidget {
  final Map<String, dynamic> patientRow;
  final VoidCallback? onUpdated;

  const PatientDentalChartFullScreenPage({
    super.key,
    required this.patientRow,
    this.onUpdated,
  });

  @override
  State<PatientDentalChartFullScreenPage> createState() =>
      _PatientDentalChartFullScreenPageState();
}

class _PatientDentalChartFullScreenPageState
    extends State<PatientDentalChartFullScreenPage> {
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
        final msg = e.toString();
        final friendly = msg.contains('Failed host lookup') ||
                msg.contains('SocketException') ||
                msg.contains('ClientException')
            ? 'No internet connection to clinic server. AI model can run offline, but creating/updating patients needs network.'
            : 'AI error: $msg';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendly), backgroundColor: Colors.red),
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
        title: Text('Patient: $_phone - Full Screen Odontogram'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.medical_services_outlined),
            tooltip: 'Start visit',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => PatientVisitScreen(patient: widget.patientRow),
                ),
              ).then((_) => widget.onUpdated?.call());
            },
          ),
          ElevatedButton.icon(
            onPressed: () {
              OdontogramPdfService.printOrShare(
                context: context,
                model: _odontogram,
                phone: _phone,
                appointment: _appointment,
                clinic: _clinic,
              );
            },
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('Export PDF'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kNavy),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveChanges,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: const Text('Save Changes'),
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

/// Full screen page for adding a new patient with Odontogram
class AddPatientFullScreenPage extends StatefulWidget {
  const AddPatientFullScreenPage({super.key});

  @override
  State<AddPatientFullScreenPage> createState() => _AddPatientFullScreenPageState();
}

class _AddPatientFullScreenPageState extends State<AddPatientFullScreenPage> {
  final _phoneController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _appointmentController = TextEditingController(text: 'Routine Dental Checkup');
  String? _sex;
  final OdontogramModel _odontogram = OdontogramModel();
  bool _saving = false;
  int _step = 0; // 0 = patient details, 1 = odontogram
  Timer? _phoneLookupDebounce;

  @override
  void dispose() {
    _phoneLookupDebounce?.cancel();
    _phoneController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _ageController.dispose();
    _appointmentController.dispose();
    super.dispose();
  }

  void _onPhoneChanged(String value) {
    _phoneLookupDebounce?.cancel();
    final phone = value.trim();
    if (phone.isEmpty) return;
    _phoneLookupDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _lookupPatientByPhone(phone),
    );
  }

  Future<void> _lookupPatientByPhone(String phone) async {
    try {
      final rows = await Supabase.instance.client
          .from('patients')
          .select('first_name, last_name, age, sex')
          .eq('phone', phone)
          .limit(1);

      if (!mounted || _phoneController.text.trim() != phone) return;
      if (rows.isEmpty) return;

      final row = rows.first;
      final sexRaw = row['sex']?.toString().trim() ?? '';
      final sexLower = sexRaw.toLowerCase();
      String? sex;
      if (sexLower.startsWith('m')) {
        sex = 'Male';
      } else if (sexLower.startsWith('f')) {
        sex = 'Female';
      }

      setState(() {
        _firstNameController.text = row['first_name']?.toString() ?? '';
        _lastNameController.text = row['last_name']?.toString() ?? '';
        _ageController.text = row['age']?.toString() ?? '';
        _sex = sex;
      });
    } catch (_) {
      // Ignore lookup failures; the user can still enter details manually.
    }
  }

  bool _validateDetails() {
    final phone = _phoneController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final ageText = _ageController.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter patient phone number'), backgroundColor: Colors.red),
      );
      return false;
    }
    if (firstName.isEmpty || lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter patient first and last name'), backgroundColor: Colors.red),
      );
      return false;
    }
    final age = int.tryParse(ageText);
    if (age == null || age <= 0 || age > 150) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid patient age'), backgroundColor: Colors.red),
      );
      return false;
    }
    if (_sex == null || _sex!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select patient sex'), backgroundColor: Colors.red),
      );
      return false;
    }
    return true;
  }

  Future<void> _savePatient() async {
    final phone = _phoneController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final age = int.tryParse(_ageController.text.trim()) ?? 0;
    final sex = _sex ?? '';

    setState(() => _saving = true);
    try {
      final diagnosisText = _odontogram.toDiagnosisSummaryString();
      final treatmentText = _odontogram.toTreatmentPlanSummaryString();
      final appointmentText = _appointmentController.text.trim();

      await Supabase.instance.client.from('patients').upsert({
        'phone': phone,
        'first_name': firstName,
        'last_name': lastName,
        'age': age,
        'sex': sex,
        'diagnosis': diagnosisText,
        'treatment_plan': _odontogram.embedInString(treatmentText),
        'appointment': appointmentText.isEmpty ? 'Pending' : appointmentText,
        'clinic': 'Dentehr Clinic',
      }, onConflict: 'phone');

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Patient $firstName $lastName ($phone) saved with Odontogram successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving patient: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goNext() {
    if (_validateDetails()) {
      setState(() => _step = 1);
    }
  }

  void _goToTreatmentPlan() {
    setState(() => _step = 2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _step == 0
              ? 'Add Patient - Patient Details'
              : _step == 1
                  ? 'Add Patient - Dental Chart (Odontogram)'
                  : 'Add Patient - Treatment Plan',
        ),
        leading: IconButton(
          icon: Icon(_step == 0 ? Icons.close : Icons.arrow_back),
          onPressed: () {
            if (_step == 0) {
              Navigator.pop(context);
            } else {
              setState(() => _step -= 1);
            }
          },
        ),
        actions: [
          if (_step >= 1)
            ElevatedButton.icon(
              onPressed: () {
                OdontogramPdfService.printOrShare(
                  context: context,
                  model: _odontogram,
                  phone: _phoneController.text.trim(),
                  appointment: _appointmentController.text.trim(),
                  clinic: 'Dentehr Clinic',
                );
              },
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Export PDF'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kNavy),
            ),
          if (_step >= 1) const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _saving
                ? null
                : (_step == 0
                    ? _goNext
                    : _step == 1
                        ? _goToTreatmentPlan
                        : _savePatient),
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_step == 2 ? Icons.save : Icons.check, size: 16),
            label: Text(
              _step == 0
                  ? 'Next: Odontogram'
                  : _step == 1
                      ? 'Next: Treatment Plan'
                      : 'Save Patient Record',
            ),
            style: ElevatedButton.styleFrom(backgroundColor: kTeal, foregroundColor: Colors.white),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _step == 0
          ? _buildDetailsStep()
          : _step == 1
              ? _buildOdontogramStep()
              : _buildTreatmentPlanStep(),
    );
  }

  Widget _buildDetailsStep() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.person_add, color: kNavy, size: 28),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Step 1 of 2', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text('Patient Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Chip(
                          label: const Text('Required', style: TextStyle(fontSize: 10)),
                          backgroundColor: Colors.red.shade50,
                          labelStyle: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      onChanged: _onPhoneChanged,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        hintText: 'e.g. +1 555 0100',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _firstNameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _lastNameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Last Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Age',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _sex,
                            decoration: const InputDecoration(
                              labelText: 'Sex',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Male', child: Text('Male (M)')),
                              DropdownMenuItem(value: 'Female', child: Text('Female (F)')),
                            ],
                            onChanged: (value) => setState(() => _sex = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _appointmentController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Appointment',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOdontogramStep() {
    return SafeArea(
      child: Column(
        children: [
          // Top Patient Header Bar
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _appointmentController,
                      decoration: const InputDecoration(
                        labelText: 'Appointment',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Full screen odontogram workspace
          Expanded(
            child: OdontogramWidget(
              model: _odontogram,
              isReadOnly: false,
              isFullScreen: true,
              patientPhone: _phoneController.text.trim(),
              appointment: _appointmentController.text.trim(),
              clinic: 'Dentehr Clinic',
              showPdfExportButton: false,
              onChanged: () => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreatmentPlanStep() {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final patientName = [firstName, lastName].where((part) => part.isNotEmpty).join(' ');
    final phone = _phoneController.text.trim();
    final treatmentMap = _odontogram.treatmentTeethMap;
    final activeTreatments = treatmentMap.entries.where((entry) => entry.value.isNotEmpty).toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: kTeal.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.assignment_outlined, color: kTeal, size: 26),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Step 3 of 3', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  Text('Treatment Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            Chip(
                              label: const Text('Review', style: TextStyle(fontSize: 10)),
                              backgroundColor: kTeal.withValues(alpha: 0.1),
                              labelStyle: const TextStyle(color: kTeal, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          patientName.isEmpty ? phone : '$patientName  •  $phone',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kNavy),
                        ),
                        const Divider(height: 24),
                        const Text('Diagnosis Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(_odontogram.toDiagnosisSummaryString(), style: const TextStyle(fontSize: 12, height: 1.4)),
                        const SizedBox(height: 16),
                        const Text('Recommended Treatment Plan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          _odontogram.toTreatmentPlanSummaryString(),
                          style: const TextStyle(fontSize: 12, height: 1.4, color: kTeal, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Treatment by Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        if (activeTreatments.isEmpty)
                          Text(
                            'No active treatment required. Preventive care and routine follow-up recommended.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                          )
                        else
                          ...activeTreatments.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 4, right: 8),
                                    decoration: const BoxDecoration(color: kTeal, shape: BoxShape.circle),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text(entry.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ),
                                  Expanded(
                                    child: Text(
                                      entry.value.join(', '),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kNavy),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => setState(() => _step = 1),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back to Odontogram'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _savePatient,
                      icon: _saving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save, size: 16),
                      label: const Text('Save Patient Record'),
                      style: ElevatedButton.styleFrom(backgroundColor: kTeal, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}