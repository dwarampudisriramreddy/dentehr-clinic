import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'odontogram/odontogram.dart';
import 'services/dental_coding_ai.dart';

const Color kVisitTeal = Color(0xFF0D9488);
const Color kVisitNavy = Color(0xFF1E3A5F);

class PatientVisitScreen extends StatefulWidget {
  final Map<String, dynamic>? patient;
  const PatientVisitScreen({super.key, this.patient});

  @override
  State<PatientVisitScreen> createState() => _PatientVisitScreenState();
}

class _PlanAppointment {
  final String treatment;
  final String teeth;
  DateTime scheduledAt;
  bool enabled = true;

  _PlanAppointment({
    required this.treatment,
    required this.teeth,
    required this.scheduledAt,
  });

  String get reason => teeth.isEmpty ? treatment : '$treatment: $teeth';
}

class _PatientVisitScreenState extends State<PatientVisitScreen> {
  static const int _lastStep = 5;

  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _appointmentController = TextEditingController();
  final _chiefComplaintController = TextEditingController();
  final _clinicalNotesController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _xrayRegionController = TextEditingController();
  final _xrayNotesController = TextEditingController();
  final _xrayImageUrlController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _amountPaidController = TextEditingController(text: '0');
  final _paymentNotesController = TextEditingController();

  String? _sex;
  int _step = 0;
  bool _saving = false;
  Timer? _phoneLookupDebounce;
  String _loadedPhone = '';
  late OdontogramModel _odontogram;

  final DentalCodingAI _ai = DentalCodingAI();
  bool _aiLoading = false;
  String _aiStatus = '';

  bool _xrayRequired = true;
  String _xrayType = 'OPG';
  String _xrayStatus = 'requested';
  final String _paymentMethod = 'Cash';
  List<_PlanAppointment> _planAppointments = [];
  int _apptSpacingMinutes = 30;

  static const List<String> _xrayTypes = ['OPG', 'IOPA', 'Periapical', 'Bitewing', 'CBCT', 'Other'];
  static const List<String> _xrayStatuses = ['requested', 'taken', 'reported'];

  @override
  void initState() {
    super.initState();
    _odontogram = OdontogramModel();
    if (widget.patient != null) {
      _applyPatient(widget.patient!);
    }
  }

  @override
  void dispose() {
    _ai.dispose();
    _phoneLookupDebounce?.cancel();
    _phoneController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _appointmentController.dispose();
    _chiefComplaintController.dispose();
    _clinicalNotesController.dispose();
    _diagnosisController.dispose();
    _xrayRegionController.dispose();
    _xrayNotesController.dispose();
    _xrayImageUrlController.dispose();
    _discountController.dispose();
    _amountPaidController.dispose();
    _paymentNotesController.dispose();
    super.dispose();
  }

  void _applyPatient(Map<String, dynamic> row) {
    _phoneController.text = row['phone']?.toString() ?? '';
    final first = row['first_name']?.toString() ?? '';
    final last = row['last_name']?.toString() ?? '';
    _nameController.text = [first, last].where((p) => p.trim().isNotEmpty).join(' ').trim();
    _ageController.text = row['age']?.toString() ?? '';
    _appointmentController.text = row['appointment']?.toString() ?? '';
    final diagnosis = OdontogramModel.cleanDisplayText(row['diagnosis']);
    _diagnosisController.text = diagnosis == 'Oral cavity clinically normal.' ? '' : diagnosis;
    final sex = row['sex']?.toString().trim().toLowerCase() ?? '';
    if (sex.startsWith('m')) {
      _sex = 'Male';
    } else if (sex.startsWith('f')) {
      _sex = 'Female';
    }
    _odontogram = OdontogramModel.fromPatientRecord(row);
    _loadedPhone = _phoneController.text.trim();
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
    if (phone == _loadedPhone && _nameController.text.trim().isNotEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('patients')
          .select()
          .eq('phone', phone)
          .limit(1);
      if (!mounted || _phoneController.text.trim() != phone || rows.isEmpty) return;
      final row = Map<String, dynamic>.from(rows.first);
      setState(() {
        _applyPatient(row);
        _diagnosisController.text = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Existing patient record loaded'), backgroundColor: Colors.green),
      );
    } catch (_) {}
  }

  DateTime _parseBaseAppointment() {
    final raw = _appointmentController.text.trim();
    final m = RegExp(r'(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})').firstMatch(raw);
    if (m != null) {
      final p = '${m.group(1)} ${m.group(2)}'.split(RegExp(r'[- :]+')).map(int.parse).toList();
      return DateTime(p[0], p[1], p[2], p[3], p[4]);
    }
    final d = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (d != null) return d.toLocal();
    return DateTime.now();
  }

  String _fmtDt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  void _generatePlanAppointments() {
    final base = _parseBaseAppointment();
    final map = _odontogram.treatmentTeethMap;
    final items = <_PlanAppointment>[];
    var i = 0;
    map.forEach((treatment, teeth) {
      if (teeth.isEmpty) return;
      items.add(_PlanAppointment(
        treatment: treatment,
        teeth: teeth.join(', '),
        scheduledAt: base.add(Duration(minutes: _apptSpacingMinutes * i)),
      ));
      i++;
    });
    setState(() => _planAppointments = items);
  }

  String get _paymentStatus => 'pending';

  bool _validatePatient() {
    if (_phoneController.text.trim().isEmpty) {
      _showError('Enter the patient phone number.');
      return false;
    }
    if (_nameController.text.trim().isEmpty) {
      _showError('Enter the patient name.');
      return false;
    }
    final age = int.tryParse(_ageController.text.trim());
    if (age == null || age <= 0 || age > 150) {
      _showError('Enter a valid patient age.');
      return false;
    }
    if (_sex == null) {
      _showError('Select the patient sex.');
      return false;
    }
    return true;
  }

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        return _validatePatient();
      case 2:
        if (_xrayRequired && _xrayRegionController.text.trim().isEmpty) {
          _showError('Enter the tooth or region for the X-ray.');
          return false;
        }
        return true;
      case 3:
        if (_diagnosisController.text.trim().isEmpty) {
          _diagnosisController.text = _odontogram.toDiagnosisSummaryString();
        }
        return true;
      default:
        return true;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _goNext() async {
    if (!_validateCurrentStep()) return;
    if (_step == 3) {
      _generatePlanAppointments();
    }
    if (!mounted) return;
    setState(() => _step = math.min(_lastStep, _step + 1));
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _step -= 1);
    }
  }

  Future<void> _saveVisit() async {
    if (!_validateCurrentStep()) return;
    setState(() => _saving = true);
    final phone = _phoneController.text.trim();
    const clinic = 'Dentehr Clinic';
    final patientName = _nameController.text.trim();
    final parts = patientName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final firstName = parts.isEmpty ? '' : parts.first;
    final lastName = parts.length <= 1 ? '' : parts.sublist(1).join(' ');
    final enabledAppts = _planAppointments.where((a) => a.enabled).toList();
    final diagnosis = _diagnosisController.text.trim().isEmpty
        ? _odontogram.toDiagnosisSummaryString()
        : _diagnosisController.text.trim();
    final xray = _xrayRequired
        ? {
            'type': _xrayType,
            'region': _xrayRegionController.text.trim(),
            'status': _xrayStatus,
            'notes': _xrayNotesController.text.trim(),
            'image_url': _xrayImageUrlController.text.trim(),
          }
        : null;
    final planText = _odontogram.toTreatmentPlanSummaryString();
    final planItems = enabledAppts.map((a) => {
      'name': a.treatment,
      'teeth': a.teeth,
      'reason': a.reason,
      'scheduled_at': a.scheduledAt.toUtc().toIso8601String(),
    }).toList();

    try {
      await Supabase.instance.client.from('visits').insert({
        'patient_phone': phone,
        'patient_name': patientName,
        'clinic': clinic,
        'visit_date': DateTime.now().toUtc().toIso8601String(),
        'chief_complaint': _chiefComplaintController.text.trim(),
        'findings': _odontogram.toDiagnosisSummaryString(),
        'clinical_notes': _clinicalNotesController.text.trim(),
        'xray': xray,
        'final_diagnosis': diagnosis,
        'treatment_plan': planItems,
        'subtotal': 0,
        'discount': 0,
        'total': 0,
        'amount_paid': 0,
        'payment_method': _paymentMethod,
        'payment_status': 'pending',
        'payment_notes': _paymentNotesController.text.trim(),
        'status': 'completed',
      });

      int apptsCreated = 0;
      String? apptError;
      for (final a in enabledAppts) {
        try {
          await Supabase.instance.client.from('appointments').insert({
            'patient_name': patientName,
            'patient_phone': phone,
            'clinic': clinic,
            'appointment_type': 'clinic',
            'status': 'pending',
            'reason': a.reason,
            'scheduled_at': a.scheduledAt.toUtc().toIso8601String(),
          });
          apptsCreated++;
        } catch (e) {
          apptError = e.toString();
        }
      }

      final age = int.tryParse(_ageController.text.trim()) ?? 0;
      final firstAppt = enabledAppts.isNotEmpty ? _fmtDt(enabledAppts.first.scheduledAt) : _appointmentController.text.trim();
      await Supabase.instance.client.from('patients').upsert({
        'phone': phone,
        'first_name': firstName,
        'last_name': lastName,
        'age': age,
        'sex': _sex ?? '',
        'diagnosis': diagnosis,
        'treatment_plan': _odontogram.embedInString(planText),
        'appointment': firstAppt.isEmpty ? 'Scheduled' : firstAppt,
        'clinic': clinic,
      }, onConflict: 'phone');

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Visit saved'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(patientName, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Final diagnosis: $diagnosis'),
              const SizedBox(height: 6),
              Text('Appointments scheduled: $apptsCreated / ${enabledAppts.length}'),
              if (apptError != null)
                Text('Some appointments failed: $apptError', style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      _showError('Could not save visit: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Visit'),
        leading: IconButton(
          icon: Icon(_step == 0 ? Icons.close : Icons.arrow_back),
          onPressed: _saving ? null : _goBack,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Step ${_step + 1} of ${_lastStep + 1}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: _step == 1
          ? _buildFindingsStep()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: _buildStep(),
                ),
              ),
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildPatientStep();
      case 2:
        return _buildXrayStep();
      case 3:
        return _buildDiagnosisStep();
      case 4:
        return _buildTreatmentStep();
      case 5:
        return _buildPaymentStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPatientStep() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepHeader(
              icon: Icons.person_search_outlined,
              step: 1,
              title: 'Patient',
              subtitle: 'Enter the phone number first. Existing findings are loaded automatically.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              onChanged: _onPhoneChanged,
              decoration: InputDecoration(
                labelText: 'Phone number',
                hintText: 'Patient gives this number at reception',
                prefixIcon: const Icon(Icons.phone),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Find patient',
                  onPressed: () {
                    _phoneLookupDebounce?.cancel();
                    unawaited(_lookupPatientByPhone(_phoneController.text.trim()));
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Age',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sex,
                    decoration: const InputDecoration(
                      labelText: 'Sex',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                    ],
                    onChanged: (value) => setState(() => _sex = value),
                  ),
                ),
              ],
            ),

          ],
        ),
      ),
    );
  }

  String _formatAppt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  void _setAppointment(DateTime dt, {String? label}) {
    setState(() {
      _appointmentController.text = label == null ? _formatAppt(dt) : '$label (${_formatAppt(dt)})';
    });
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

  Future<void> _ensureOdontogramAiModel() async {
    if (_ai.isReady) return;
    if (_ai.requiresModelFile) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Pick AI model file (.litertlm)',
      );
      if (result == null || result.files.single.path == null) {
        throw Exception('No model file selected');
      }
      await _ai.initModel(
        modelPath: result.files.single.path!,
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

  Future<void> _runOdontogramAi() async {
    final promptController = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI chart assistant'),
        content: TextField(
          controller: promptController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'e.g. "Tooth 36 has pulpitis, 11 and 21 decayed"',
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

    setState(() {
      _aiLoading = true;
      _aiStatus = 'Starting...';
    });
    try {
      if (!_ai.isReady) {
        if (mounted) {
          setState(() => _aiStatus = _ai.requiresModelFile
              ? 'Pick a model file...'
              : 'Initializing Web AI (first run may download model)...');
        }
        await _ensureOdontogramAiModel();
      }
      if (mounted) setState(() => _aiStatus = 'Thinking...');
      final result = await _ai.interpretOdontogramPrompt(
        prompt,
        _odontogram.toDiagnosisSummaryString(),
      );
      final reply = (result['reply'] ?? '').toString();
      final changes = result['changes'] is List ? result['changes'] as List : const [];
      var applied = 0;
      for (final c in changes) {
        if (c is! Map) continue;
        final tooth = _normalizeTooth(c['tooth']);
        final cat = _normalizeCategory(c['category']);
        if (RegExp(r'^(1[1-8]|2[1-8]|3[1-8]|4[1-8])$').hasMatch(tooth) &&
            cat.isNotEmpty &&
            cat != 'Normal') {
          final existing = _odontogram.getTeethStringForCategory(cat);
          final merged = existing.isEmpty ? tooth : '$existing, $tooth';
          _odontogram.setTeethForCategory(cat, merged);
          applied++;
        }
      }
      if (mounted) {
        final isDiagnose = (result['action'] ?? '').toString() == 'diagnose';
        setState(() {
          if (applied == 0 &&
              isDiagnose &&
              reply.isNotEmpty &&
              _diagnosisController.text.trim().isEmpty) {
            _diagnosisController.text = reply;
          }
          _aiLoading = false;
          _aiStatus = '';
        });
        if (applied == 0 && reply.isNotEmpty) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('AI diagnosis'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Text(reply, style: const TextStyle(fontSize: 14, height: 1.4)),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ],
            ),
          );
        } else {
          final msg = reply.isEmpty ? 'AI chart updated' : reply;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(applied > 0 ? '$msg (applied $applied)' : msg)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiLoading = false;
          _aiStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildFindingsStep() {
    final appt = _appointmentController.text.trim();
    return SafeArea(
      child: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 18, color: kVisitNavy),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _patientLabel(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      const Text(
                        'Mark findings on the chart',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: _aiLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome, size: 16, color: kVisitTeal),
                        label: Text(_aiLoading ? 'AI...' : 'AI', style: const TextStyle(fontSize: 11)),
                        tooltip: _aiStatus.isEmpty ? 'AI chart assistant' : _aiStatus,
                        visualDensity: VisualDensity.compact,
                        onPressed: _aiLoading ? null : _runOdontogramAi,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(Icons.event, size: 16, color: kVisitTeal),
                      const Text('Appointment:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ActionChip(label: const Text('Now'), visualDensity: VisualDensity.compact,
                        onPressed: () => _setAppointment(DateTime.now(), label: 'Now')),
                      ActionChip(label: const Text('5 mins'), visualDensity: VisualDensity.compact,
                        onPressed: () => _setAppointment(DateTime.now().add(const Duration(minutes: 5)), label: 'In 5 mins')),
                      ActionChip(label: const Text('Tomorrow'), visualDensity: VisualDensity.compact,
                        onPressed: () => _setAppointment(DateTime.now().add(const Duration(days: 1)), label: 'Tomorrow')),
                      if (appt.isNotEmpty)
                        Text(appt, style: const TextStyle(fontSize: 11, color: kVisitNavy)),
                    ],
                  ),
                ],
              ),
            ),
          ),
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

  Widget _buildXrayStep() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StepHeader(
              icon: Icons.image_outlined,
              step: 3,
              title: 'Raise X-ray',
              subtitle: 'Request the required radiograph and record its status.',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('X-ray required'),
              subtitle: const Text('Turn off if no radiograph is needed for this visit.'),
              value: _xrayRequired,
              onChanged: (value) => setState(() => _xrayRequired = value),
            ),
            if (_xrayRequired) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _xrayType,
                      decoration: const InputDecoration(
                        labelText: 'X-ray type',
                        border: OutlineInputBorder(),
                      ),
                      items: _xrayTypes
                          .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                          .toList(),
                      onChanged: (value) => setState(() => _xrayType = value ?? _xrayType),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _xrayStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: _xrayStatuses
                          .map((status) => DropdownMenuItem(
                                value: status,
                                child: Text(_capitalize(status)),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _xrayStatus = value ?? _xrayStatus),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _xrayRegionController,
                decoration: const InputDecoration(
                  labelText: 'Tooth / region',
                  hintText: 'e.g. 36, 37 or full mouth',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _xrayNotesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Radiographer notes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _xrayImageUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'X-ray image link (optional)',
                  hintText: 'Paste a link to the stored image',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosisStep() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StepHeader(
              icon: Icons.assignment_turned_in_outlined,
              step: 4,
              title: 'Final diagnosis',
              subtitle: 'Review the chart findings and record the dentist diagnosis.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _chiefComplaintController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Chief complaint',
                hintText: 'What the patient reports',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clinicalNotesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Clinical notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _diagnosisController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Final diagnosis',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _diagnosisController.text = _odontogram.toDiagnosisSummaryString();
                }),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Use odontogram findings'),
              ),
            ),
            const Divider(height: 24),
            const Text('Findings from odontogram', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              _odontogram.toDiagnosisSummaryString(),
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTreatmentStep() {
    if (_planAppointments.isEmpty) {
      _generatePlanAppointments();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          icon: Icons.medical_services_outlined,
          step: 5,
          title: 'Treatment plan & appointments',
          subtitle: 'Each treatment from the odontogram becomes its own appointment. Adjust times and disable what should not be scheduled.',
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          color: kVisitTeal.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Plan from odontogram', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  _odontogram.toTreatmentPlanSummaryString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.4),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Spacing:', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _apptSpacingMinutes,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 15, child: Text('15 min')),
                        DropdownMenuItem(value: 30, child: Text('30 min')),
                        DropdownMenuItem(value: 45, child: Text('45 min')),
                        DropdownMenuItem(value: 60, child: Text('1 hour')),
                        DropdownMenuItem(value: 1440, child: Text('1 day')),
                      ],
                      onChanged: (v) => setState(() {
                        _apptSpacingMinutes = v ?? 30;
                        _planAppointments.clear();
                      }),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() => _planAppointments.clear()),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Regenerate', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_planAppointments.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No treatment findings on the odontogram. Go back and mark findings, or save the visit without appointments.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          )
        else
          ..._planAppointments.map(
            (appt) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: appt.enabled,
                          onChanged: (v) => setState(() => appt.enabled = v ?? false),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appt.treatment,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: appt.enabled ? null : Colors.grey,
                                ),
                              ),
                              if (appt.teeth.isNotEmpty)
                                Text('Teeth: ${appt.teeth}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(Icons.event, size: 16, color: kVisitTeal),
                        Text(_fmtDt(appt.scheduledAt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ActionChip(
                          label: const Text('+1 day', style: TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => appt.scheduledAt = appt.scheduledAt.add(const Duration(days: 1))),
                        ),
                        ActionChip(
                          label: const Text('+1 hour', style: TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => appt.scheduledAt = appt.scheduledAt.add(const Duration(hours: 1))),
                        ),
                        ActionChip(
                          label: const Text('Now', style: TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => appt.scheduledAt = DateTime.now()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentStep() {
    final enabledAppts = _planAppointments.where((a) => a.enabled).toList();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StepHeader(
              icon: Icons.event_available_outlined,
              step: 6,
              title: 'Appointments',
              subtitle: 'Confirm the appointments that will be created for each treatment.',
            ),
            const SizedBox(height: 16),
            if (enabledAppts.isEmpty)
              Text(
                'No appointments will be created. You can still save the visit.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              )
            else
              ...enabledAppts.map(
                (appt) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 16, color: kVisitTeal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          appt.teeth.isEmpty ? appt.treatment : '${appt.treatment} (${appt.teeth})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(_fmtDt(appt.scheduledAt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            const Divider(height: 24),
            TextField(
              controller: _paymentNotesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Appointments to create: ', style: TextStyle(fontSize: 12)),
                _PaymentChip(status: _paymentStatus),
                const Spacer(),
                Text(
                  '${enabledAppts.length}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kVisitNavy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_step >= 4)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      '${_planAppointments.where((a) => a.enabled).length} appointment(s)',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const Spacer(),
                    Text(
                      _planAppointments.isEmpty ? 'No plan from odontogram' : 'One appointment per treatment',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                if (_step > 0)
                  OutlinedButton(
                    onPressed: _saving ? null : _goBack,
                    child: const Text('Back'),
                  ),
                const Spacer(),
                if (_step < _lastStep)
                  FilledButton.icon(
                    onPressed: _saving ? null : _goNext,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(_bottomNextLabel()),
                    style: FilledButton.styleFrom(backgroundColor: kVisitTeal),
                  )
                else
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveVisit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_saving ? 'Saving...' : 'Save visit & schedule appointments'),
                    style: FilledButton.styleFrom(backgroundColor: kVisitTeal),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _bottomNextLabel() {
    switch (_step) {
      case 0:
        return 'Next: Findings';
      case 1:
        return 'Next: X-ray';
      case 2:
        return 'Next: Diagnosis';
      case 3:
        return 'Next: Treatment plan';
      case 4:
        return 'Next: Appointments';
      default:
        return 'Next';
    }
  }

  String _patientLabel() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty) return phone;
    return '$name • $phone';
  }
}

class _StepHeader extends StatelessWidget {
  final IconData icon;
  final int step;
  final String title;
  final String subtitle;

  const _StepHeader({
    required this.icon,
    required this.step,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kVisitTeal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: kVisitTeal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Step $step', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final String status;
  const _PaymentChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'paid'
        ? Colors.green
        : status == 'partial'
            ? Colors.orange
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        _capitalize(status),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
