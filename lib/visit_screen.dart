import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'odontogram/odontogram.dart';

const Color kVisitTeal = Color(0xFF0D9488);
const Color kVisitNavy = Color(0xFF1E3A5F);

class PatientVisitScreen extends StatefulWidget {
  final Map<String, dynamic>? patient;
  const PatientVisitScreen({super.key, this.patient});

  @override
  State<PatientVisitScreen> createState() => _PatientVisitScreenState();
}

class _VisitTreatment {
  final String id;
  final String name;
  final String category;
  final String description;
  final double cost;
  final bool available;
  bool selected = false;
  int quantity = 1;

  _VisitTreatment({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.cost,
    required this.available,
  });
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
  bool _loadingTreatments = false;
  String? _treatmentError;
  String _treatmentSearch = '';
  String _treatmentsClinic = '';
  Timer? _phoneLookupDebounce;
  String _loadedPhone = '';
  late OdontogramModel _odontogram;

  bool _xrayRequired = true;
  String _xrayType = 'OPG';
  String _xrayStatus = 'requested';
  String _paymentMethod = 'Cash';
  List<_VisitTreatment> _treatments = [];

  static const List<String> _xrayTypes = ['OPG', 'IOPA', 'Periapical', 'Bitewing', 'CBCT', 'Other'];
  static const List<String> _xrayStatuses = ['requested', 'taken', 'reported'];
  static const List<String> _paymentMethods = ['Cash', 'Card', 'UPI', 'Bank transfer', 'Insurance'];

  @override
  void initState() {
    super.initState();
    _odontogram = OdontogramModel();
    if (widget.patient != null) {
      _applyPatient(widget.patient!);
    }
    _loadTreatments();
  }

  @override
  void dispose() {
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

  Future<void> _loadTreatments() async {
    const clinic = 'Dentehr Clinic';
    setState(() {
      _loadingTreatments = true;
      _treatmentError = null;
    });
    try {
      final catalog = await Supabase.instance.client.from('treatments').select().order('category');
      List<Map<String, dynamic>> overrides = [];
      try {
        final rows = await Supabase.instance.client
            .from('clinic_treatments')
            .select()
            .eq('clinic', clinic);
        overrides = List<Map<String, dynamic>>.from(rows);
      } catch (_) {}

      final items = <_VisitTreatment>[];
      for (final treatment in catalog) {
        final id = treatment['id']?.toString() ?? '';
        Map<String, dynamic>? override;
        for (final row in overrides) {
          if (row['treatment_id']?.toString() == id) {
            override = row;
            break;
          }
        }
        final availability = (override?['availability'] ?? treatment['availability'] ?? 'available')
            .toString()
            .toLowerCase();
        final isActive = (override?['is_active'] ?? treatment['is_active'] ?? true) == true;
        items.add(
          _VisitTreatment(
            id: id,
            name: treatment['name']?.toString() ?? 'Treatment',
            category: treatment['category']?.toString() ?? 'General',
            description: treatment['description']?.toString() ?? '',
            cost: (override?['cost'] as num?)?.toDouble() ??
                (treatment['cost'] as num?)?.toDouble() ??
                0,
            available: isActive && availability != 'unavailable',
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _treatments = items;
        _treatmentsClinic = clinic;
        _loadingTreatments = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingTreatments = false;
        _treatmentError = error.toString();
      });
    }
  }

  double get _subtotal => _treatments
      .where((treatment) => treatment.selected)
      .fold(0, (sum, treatment) => sum + treatment.cost * treatment.quantity);

  double get _discount {
    final value = double.tryParse(_discountController.text.trim()) ?? 0;
    return value.clamp(0, _subtotal);
  }

  double get _total => math.max(0, _subtotal - _discount);

  double get _amountPaid {
    final value = double.tryParse(_amountPaidController.text.trim()) ?? 0;
    return math.max(0, value);
  }

  String get _paymentStatus {
    if (_total <= 0) return 'paid';
    if (_amountPaid <= 0) return 'unpaid';
    if (_amountPaid < _total) return 'partial';
    return 'paid';
  }

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
      case 5:
        if (_amountPaid > _total) {
          _showError('Amount paid cannot be more than the treatment total.');
          return false;
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
    if (_step == 3 && _treatmentsClinic != 'Dentehr Clinic') {
      await _loadTreatments();
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
    final selected = _treatments.where((treatment) => treatment.selected).toList();
    final planItems = selected
        .map(
          (treatment) => {
            'treatment_id': treatment.id,
            'name': treatment.name,
            'category': treatment.category,
            'unit_cost': treatment.cost,
            'quantity': treatment.quantity,
            'line_total': treatment.cost * treatment.quantity,
          },
        )
        .toList();
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
    final planText = [
      _odontogram.toTreatmentPlanSummaryString(),
      if (selected.isNotEmpty)
        selected.map((treatment) => '${treatment.name} x${treatment.quantity}').join(', '),
    ].where((part) => part.isNotEmpty).join(' | ');

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
        'subtotal': _subtotal,
        'discount': _discount,
        'total': _total,
        'amount_paid': _amountPaid,
        'payment_method': _paymentMethod,
        'payment_status': _paymentStatus,
        'payment_notes': _paymentNotesController.text.trim(),
        'status': 'completed',
      });

      final age = int.tryParse(_ageController.text.trim()) ?? 0;
      await Supabase.instance.client.from('patients').upsert({
        'phone': phone,
        'first_name': firstName,
        'last_name': lastName,
        'age': age,
        'sex': _sex ?? '',
        'diagnosis': diagnosis,
        'treatment_plan': _odontogram.embedInString(planText),
        'appointment': _appointmentController.text.trim().isEmpty
            ? 'Completed'
            : _appointmentController.text.trim(),
        'clinic': clinic,
      }, onConflict: 'phone');

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Visit completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(patientName, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Final diagnosis: $diagnosis'),
              const SizedBox(height: 6),
              Text('Treatment total: \$${_total.toStringAsFixed(2)}'),
              Text('Amount paid: \$${_amountPaid.toStringAsFixed(2)}'),
              Text('Payment status: ${_capitalize(_paymentStatus)}'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
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

  Widget _buildFindingsStep() {
    return SafeArea(
      child: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
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
    final query = _treatmentSearch.toLowerCase();
    final filtered = _treatments.where((treatment) {
      if (query.isEmpty) return true;
      return treatment.name.toLowerCase().contains(query) ||
          treatment.category.toLowerCase().contains(query) ||
          treatment.description.toLowerCase().contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          icon: Icons.medical_services_outlined,
          step: 5,
          title: 'Treatment plan',
          subtitle: 'Select the treatments to perform and set quantities.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search treatments...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (value) => setState(() => _treatmentSearch = value),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh treatments',
              onPressed: _loadingTreatments ? null : _loadTreatments,
              icon: _loadingTreatments
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_treatmentError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Could not load treatments: $_treatmentError',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        const SizedBox(height: 10),
        if (_loadingTreatments)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (filtered.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No treatments found')))
        else
          ...filtered.map(
            (treatment) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: CheckboxListTile(
                value: treatment.selected,
                onChanged: treatment.available
                    ? (value) => setState(() => treatment.selected = value ?? false)
                    : null,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  treatment.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: treatment.available ? null : Colors.grey,
                  ),
                ),
                subtitle: Text(
                  '${treatment.category} • \$${treatment.cost.toStringAsFixed(2)}'
                  '${treatment.available ? '' : ' • unavailable'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                secondary: treatment.selected
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: treatment.quantity > 1
                                ? () => setState(() => treatment.quantity -= 1)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                          ),
                          Text('${treatment.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => treatment.quantity += 1),
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentStep() {
    final selected = _treatments.where((treatment) => treatment.selected).toList();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StepHeader(
              icon: Icons.payments_outlined,
              step: 6,
              title: 'Payment',
              subtitle: 'Record the amount received for the completed treatment.',
            ),
            const SizedBox(height: 16),
            if (selected.isEmpty)
              Text(
                'No treatment selected. You can still save the visit with no charge.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              )
            else
              ...selected.map(
                (treatment) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${treatment.name} x${treatment.quantity}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '\$${(treatment.cost * treatment.quantity).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 24),
            _totalRow('Subtotal', _subtotal),
            const SizedBox(height: 10),
            TextField(
              controller: _discountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Discount',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            _totalRow('Total', _total, bold: true),
            const SizedBox(height: 16),
            TextField(
              controller: _amountPaidController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Amount paid now',
                prefixText: '\$ ',
                border: const OutlineInputBorder(),
                suffixIcon: TextButton(
                  onPressed: () => setState(() {
                    _amountPaidController.text = _total.toStringAsFixed(2);
                  }),
                  child: const Text('Pay full'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                border: OutlineInputBorder(),
              ),
              items: _paymentMethods
                  .map((method) => DropdownMenuItem(value: method, child: Text(method)))
                  .toList(),
              onChanged: (value) => setState(() => _paymentMethod = value ?? _paymentMethod),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _paymentNotesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Payment notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Payment status: ', style: TextStyle(fontSize: 12)),
                _PaymentChip(status: _paymentStatus),
                const Spacer(),
                Text(
                  'Balance: \$${math.max(0, _total - _amountPaid).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                      '${_treatments.where((t) => t.selected).length} treatment(s)',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const Spacer(),
                    Text(
                      'Total: \$${_total.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kVisitNavy),
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
                    label: Text(_saving ? 'Saving...' : 'Save visit & payment'),
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
        return 'Next: Payment';
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

  Widget _totalRow(String label, double value, {bool bold = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 14 : 12),
        ),
        const Spacer(),
        Text(
          '\$${value.toStringAsFixed(2)}',
          style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 14 : 12),
        ),
      ],
    );
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
