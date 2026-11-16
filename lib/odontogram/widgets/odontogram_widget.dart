import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../services/dental_coding_ai.dart';
import '../models/odontogram_model.dart';
import '../services/odontogram_pdf_service.dart';
import 'odontogram_painter.dart';

class OdontogramWidget extends StatefulWidget {
  final OdontogramModel model;
  final bool isReadOnly;
  final VoidCallback? onChanged;
  final String? patientPhone;
  final String? appointment;
  final String? clinic;
  final bool showPdfExportButton;
  final bool isFullScreen;

  const OdontogramWidget({
    super.key,
    required this.model,
    this.isReadOnly = false,
    this.onChanged,
    this.patientPhone,
    this.appointment,
    this.clinic,
    this.showPdfExportButton = true,
    this.isFullScreen = true,
  });

  @override
  State<OdontogramWidget> createState() => _OdontogramWidgetState();
}

class _OdontogramWidgetState extends State<OdontogramWidget> {
  String? _selectedTooth;
  bool _showComplaintsSection = false;

  // Text editing controllers for TUI keyboard inputs
  final Map<String, TextEditingController> _tuiControllers = {};
  final Map<String, FocusNode> _tuiFocusNodes = {};
  bool _isSyncing = false;

  static const List<String> _tuiCategories = [
    'Decayed',
    'Fracture',
    'Pulpitis',
    'Abscess',
    'Periodontitis',
    'Attrition',
    'Abrasion',
    'Root Stump',
    'Impacted',
    'Missing',
    'Treated',
    'Mobility',
    'Recession',
    'Pocket',
    'Calculus',
  ];

  // AI assistant
  final TextEditingController _aiPromptController = TextEditingController();
  final DentalCodingAI _ai = DentalCodingAI();
  bool _aiLoading = false;
  bool _aiRunning = false;
  String? _aiReply;

  @override
  void initState() {
    super.initState();
    _initTuiControllers();
  }

  void _initTuiControllers() {
    for (final cat in _tuiCategories) {
      _tuiControllers[cat] = TextEditingController(
        text: widget.model.getTeethStringForCategory(cat),
      );
      final focusNode = FocusNode();
      focusNode.addListener(() {
        if (mounted) setState(() {});
      });
      _tuiFocusNodes[cat] = focusNode;
    }
  }

  String? _activeTuiCategory;

  @override
  void didUpdateWidget(covariant OdontogramWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTuiControllersFromModel(excludeCategory: _activeTuiCategory);
  }

  @override
  void dispose() {
    for (final c in _tuiControllers.values) {
      c.dispose();
    }
    for (final f in _tuiFocusNodes.values) {
      f.dispose();
    }
    _aiPromptController.dispose();
    _ai.dispose();
    super.dispose();
  }

  void _syncTuiControllersFromModel({String? excludeCategory}) {
    if (_isSyncing) return;
    _isSyncing = true;
    for (final cat in _tuiCategories) {
      if (cat == excludeCategory) continue;
      final text = widget.model.getTeethStringForCategory(cat);
      final ctrl = _tuiControllers[cat];
      if (ctrl != null && ctrl.text != text) {
        ctrl.value = ctrl.value.copyWith(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
    _isSyncing = false;
  }

  void _notifyChange({String? sourceTuiCategory}) {
    _syncTuiControllersFromModel(excludeCategory: sourceTuiCategory);
    setState(() {});
    widget.onChanged?.call();
  }

  void _onTuiCategoryChanged(String category, String value) {
    _isSyncing = true;
    widget.model.setTeethForCategory(category, value);
    _syncTuiControllersFromModel(excludeCategory: category);
    _isSyncing = false;
    _notifyChange(sourceTuiCategory: category);
  }

  // --- AI assistant ---
  Future<void> _pickModelFile() async {
    setState(() {
      _aiLoading = true;
      _aiReply = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        dialogTitle: 'Select AI model (.litertlm) from storage',
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _aiReply = 'No model selected.');
        return;
      }
      final path = result.files.single.path;
      if (path == null || path.isEmpty) {
        if (mounted) {
          setState(() => _aiReply =
              'Could not access file path. Copy the .litertlm file to device storage and try again.');
        }
        return;
      }
      if (!path.toLowerCase().endsWith('.litertlm')) {
        if (mounted) {
          setState(() => _aiReply = 'Please select a .litertlm model file.');
        }
        return;
      }
      await _ai.initModel(
        modelPath: path,
        onLog: (msg) {
          if (mounted) setState(() => _aiReply = msg);
        },
      );
      if (mounted) {
        setState(() => _aiReply =
            'AI ready: ${_ai.modelName}. Type a prompt to diagnose or update the odontogram.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aiReply = 'Failed to load model: $e');
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _runAiPrompt() async {
    final prompt = _aiPromptController.text.trim();
    if (prompt.isEmpty || widget.isReadOnly || _aiRunning) return;
    if (!_ai.isReady) {
      await _pickModelFile();
      if (!_ai.isReady) return;
    }
    setState(() => _aiRunning = true);
    try {
      final summary = widget.model.toDiagnosisSummaryString();
      final result = await _ai.interpretOdontogramPrompt(prompt, summary);
      final action = (result['action'] ?? 'diagnose').toString().toLowerCase();
      final reply = (result['reply'] ?? '').toString();
      final changes = result['changes'];
      int applied = 0;
      if (action == 'update' && changes is List) {
        for (final c in changes) {
          if (c is! Map) continue;
          final tooth = _normalizeTooth(c['tooth']);
          final category = _normalizeCategory(c['category']?.toString() ?? '');
          if (tooth == null || category == null) continue;
          _applyAiChange(tooth, category);
          applied++;
        }
        _syncTuiControllersFromModel();
        _notifyChange();
      }
      if (mounted) {
        setState(() {
          _aiReply = reply.isNotEmpty
              ? (action == 'update'
                  ? '$reply${applied > 0 ? ' (applied $applied change${applied == 1 ? '' : 's'})' : ''}'
                  : reply)
              : (action == 'diagnose'
                  ? summary
                  : 'Applied $applied change${applied == 1 ? '' : 's'}.');
        });
      }
    } catch (e) {
      if (mounted) setState(() => _aiReply = 'AI error: $e');
    } finally {
      if (mounted) setState(() => _aiRunning = false);
    }
  }

  String? _normalizeTooth(dynamic t) {
    if (t == null) return null;
    final s = t.toString().trim();
    return RegExp(r'^(1[1-8]|2[1-8]|3[1-8]|4[1-8]|5[1-5]|6[1-5]|7[1-5]|8[1-5])$')
            .hasMatch(s)
        ? s
        : null;
  }

  String? _normalizeCategory(String c) {
    final v = c.trim().toLowerCase().replaceAll('_', ' ');
    const map = {
      'decayed': 'Decayed',
      'decay': 'Decayed',
      'caries': 'Decayed',
      'dental caries': 'Decayed',
      'missing': 'Missing',
      'extracted': 'Missing',
      'treated': 'Treated',
      'restored': 'Treated',
      'filled': 'Treated',
      'pulpitis': 'Pulpitis',
      'abscess': 'Abscess',
      'periapical abscess': 'Abscess',
      'fracture': 'Fracture',
      'periodontitis': 'Periodontitis',
      'attrition': 'Attrition',
      'abrasion': 'Abrasion',
      'root stump': 'Root Stump',
      'impacted': 'Impacted',
      'mobility': 'Mobility',
      'recession': 'Recession',
      'pocket': 'Pocket',
      'normal': 'Normal',
    };
    return map[v];
  }

  void _applyAiChange(String tooth, String category) {
    switch (category) {
      case 'Normal':
        widget.model.setCondition(tooth, ToothCondition.none);
        widget.model.toothFindings.remove(tooth);
        return;
      case 'Missing':
        widget.model.setCondition(tooth, ToothCondition.missing);
        widget.model.toothFindings.remove(tooth);
        return;
      case 'Treated':
        widget.model.setCondition(tooth, ToothCondition.treated);
        widget.model.getFinding(tooth).treatmentType ??= 'restored';
        return;
      case 'Decayed':
        widget.model.setCondition(tooth, ToothCondition.abnormal);
        final f = widget.model.getFinding(tooth);
        f.isDecayed = true;
        if (f.decayAreas.isEmpty) f.decayAreas.add('occlusal');
        return;
      case 'Fracture':
        widget.model.setCondition(tooth, ToothCondition.abnormal);
        widget.model.getFinding(tooth).isFracture = true;
        return;
      case 'Attrition':
        widget.model.setCondition(tooth, ToothCondition.abnormal);
        widget.model.getFinding(tooth).isAttrition = true;
        return;
      case 'Abrasion':
        widget.model.setCondition(tooth, ToothCondition.abnormal);
        widget.model.getFinding(tooth).isAbrasion = true;
        return;
      case 'Root Stump':
        widget.model.setCondition(tooth, ToothCondition.abnormal);
        widget.model.getFinding(tooth).isRootStump = true;
        return;
      case 'Impacted':
        widget.model.setCondition(tooth, ToothCondition.abnormal);
        widget.model.getFinding(tooth).isImpacted = true;
        return;
      case 'Pulpitis':
      case 'Abscess':
      case 'Periodontitis':
        widget.model.setCondition(tooth, ToothCondition.abnormal);
        widget.model.getFinding(tooth).specificDiagnosis = category;
        return;
      case 'Mobility':
        widget.model.getFinding(tooth).mobility = true;
        return;
      case 'Recession':
        widget.model.getFinding(tooth).recession = true;
        return;
      case 'Pocket':
        widget.model.getFinding(tooth).pocket = true;
        return;
    }
  }

  Widget _buildAiAssistantCard() {
    if (widget.isReadOnly) return const SizedBox.shrink();
    final hasModel = _ai.isReady;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasModel ? 'AI: ${_ai.modelName}' : 'AI Assistant (change chart / diagnosis)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: (_aiLoading || _aiRunning) ? null : _pickModelFile,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: Text(hasModel ? 'Change model' : 'Pick model'),
                ),
              ],
            ),
            Text(
              'Pick a .litertlm model file from device storage, then ask to diagnose or update the chart. '
              'Examples: "mark 16 as decayed", "tooth 26 missing", "diagnose this chart".',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _aiPromptController,
                    minLines: 1,
                    maxLines: 3,
                    enabled: hasModel && !_aiRunning && !_aiLoading,
                    decoration: InputDecoration(
                      hintText: hasModel
                          ? 'Enter prompt to change odontogram or ask for diagnosis...'
                          : 'Pick a model file to enable prompts...',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onSubmitted: (_) => _runAiPrompt(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: (_aiRunning || _aiLoading) ? null : _runAiPrompt,
                  icon: (_aiRunning || _aiLoading)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 16),
                  label: Text(hasModel ? 'Ask AI' : 'Pick & Ask'),
                ),
              ],
            ),
            if (_aiReply != null || _ai.debugLogs.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (_aiReply != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: SelectableText(_aiReply!,
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                ),
              if (_ai.debugLogs.isNotEmpty) ...[
                const SizedBox(height: 6),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  initiallyExpanded: _aiLoading,
                  title: Text(
                    'Debug log (${_ai.debugLogs.length})',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 180),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _ai.debugLogs.join('\n'),
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.3,
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // --- GUI touch & long press handlers ---
  void _onCanvasTap(TapUpDetails details, Size size) {
    if (widget.isReadOnly) {
      final tooth = OdontogramGeometry.instance.hitTest(
        details.localPosition,
        size,
        widget.model.visibleTeeth,
      );
      if (tooth != null) {
        setState(() => _selectedTooth = tooth);
      }
      return;
    }

    final tooth = OdontogramGeometry.instance.hitTest(
      details.localPosition,
      size,
      widget.model.visibleTeeth,
    );

    if (tooth != null) {
      setState(() => _selectedTooth = tooth);
      _openToothDialog(tooth);
    }
  }

  void _onCanvasLongPress(LongPressEndDetails details, Size size) {
    final tooth = OdontogramGeometry.instance.hitTest(
      details.localPosition,
      size,
      widget.model.visibleTeeth,
    );

    if (tooth != null) {
      setState(() => _selectedTooth = tooth);
      _openToothDialog(tooth);
    }
  }

  void _openToothDialog(String toothId) {
    final currentCond = widget.model.getCondition(toothId);
    final finding = widget.model.getFinding(toothId).clone();
    ToothCondition selectedCondition = currentCond;

    if (selectedCondition == ToothCondition.treated && finding.treatmentType == null) {
      finding.treatmentType = 'restored';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final showInvolvement = finding.isDecayed || finding.isFracture;
          final cariesEval = OdontogramModel.evaluateCaries(finding.decayAreas);

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.medical_information, color: Colors.blue, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tooth $toothId Assessment', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        'Select condition & clinical findings',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tooth Condition:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          avatar: const Icon(Icons.check_circle_outline, size: 16, color: Colors.teal),
                          label: const Text('Normal'),
                          selected: selectedCondition == ToothCondition.none,
                          selectedColor: Colors.teal.shade100,
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedCondition = ToothCondition.none);
                          },
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.error_outline, size: 16, color: Colors.red),
                          label: const Text('Abnormal / Caries'),
                          selected: selectedCondition == ToothCondition.abnormal,
                          selectedColor: Colors.red.shade100,
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedCondition = ToothCondition.abnormal);
                          },
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.cancel_outlined, size: 16, color: Colors.black87),
                          label: const Text('Missing'),
                          selected: selectedCondition == ToothCondition.missing,
                          selectedColor: Colors.grey.shade300,
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedCondition = ToothCondition.missing);
                          },
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.healing, size: 16, color: Colors.green),
                          label: const Text('Treated'),
                          selected: selectedCondition == ToothCondition.treated,
                          selectedColor: Colors.green.shade100,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                selectedCondition = ToothCondition.treated;
                                finding.treatmentType ??= 'restored';
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    if (selectedCondition == ToothCondition.none) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.teal, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Tooth $toothId is clinically healthy and normal. Saving will mark this tooth as normal and clear prior abnormal findings.',
                                style: TextStyle(fontSize: 12, color: Colors.teal.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (selectedCondition == ToothCondition.missing) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.remove_circle, color: Colors.black87, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Tooth $toothId will be recorded as Missing (Extracted or Congenitally Absent).',
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (selectedCondition == ToothCondition.treated) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Treatment History & Restorations',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: finding.treatmentType ?? 'restored',
                              decoration: const InputDecoration(
                                labelText: 'Treatment Type',
                                isDense: true,
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'restored', child: Text('Restored (Dental Filling)')),
                                DropdownMenuItem(value: 'filled', child: Text('Root Canal Filled')),
                                DropdownMenuItem(value: 'implant', child: Text('Dental Implant')),
                                DropdownMenuItem(value: 'fpd', child: Text('Fixed Partial Denture (Bridge / Crown)')),
                              ],
                              onChanged: (v) => setDialogState(() => finding.treatmentType = v),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Treatment Failure (Retreatment Needed)'),
                              value: finding.hasFailure,
                              onChanged: (val) => setDialogState(() => finding.hasFailure = val ?? false),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const Text('Dental Conditions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Decay (Dental Caries)'),
                        value: finding.isDecayed,
                        onChanged: (val) {
                          setDialogState(() {
                            finding.isDecayed = val ?? false;
                            if (finding.isDecayed && finding.decayAreas.isEmpty) {
                              finding.decayAreas.add('occlusal');
                            }
                          });
                        },
                      ),
                      if (finding.isDecayed) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Caries Involving Areas:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                children: ['occlusal', 'buccal', 'mesial', 'distal', 'lingual'].map((area) {
                                  final isSelected = finding.decayAreas.contains(area);
                                  return FilterChip(
                                    label: Text(area[0].toUpperCase() + area.substring(1)),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setDialogState(() {
                                        if (selected) {
                                          finding.decayAreas.add(area);
                                        } else {
                                          finding.decayAreas.remove(area);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Evaluated: ${cariesEval.diagnosis}\nRecommendation: ${cariesEval.treatment}',
                                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Fracture'),
                        value: finding.isFracture,
                        onChanged: (val) => setDialogState(() => finding.isFracture = val ?? false),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Attrition'),
                        value: finding.isAttrition,
                        onChanged: (val) => setDialogState(() => finding.isAttrition = val ?? false),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Abrasion'),
                        value: finding.isAbrasion,
                        onChanged: (val) => setDialogState(() => finding.isAbrasion = val ?? false),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Non-vital'),
                        value: finding.isNonVital,
                        onChanged: (val) => setDialogState(() => finding.isNonVital = val ?? false),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Developmental Anomalies'),
                        value: finding.isAnomalies,
                        onChanged: (val) => setDialogState(() => finding.isAnomalies = val ?? false),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Root Stump'),
                        value: finding.isRootStump,
                        onChanged: (val) => setDialogState(() => finding.isRootStump = val ?? false),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Impacted'),
                        value: finding.isImpacted,
                        onChanged: (val) => setDialogState(() => finding.isImpacted = val ?? false),
                      ),
                      if (showInvolvement) ...[
                        const Divider(),
                        const Text('Clinical Involvement Scores', style: TextStyle(fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: finding.pain,
                                decoration: const InputDecoration(labelText: 'Pain (P)', isDense: true),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('0 - None')),
                                  DropdownMenuItem(value: 1, child: Text('1 - Mild')),
                                  DropdownMenuItem(value: 2, child: Text('2 - Severe')),
                                ],
                                onChanged: (v) => setDialogState(() => finding.pain = v ?? 0),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: finding.top,
                                decoration: const InputDecoration(labelText: 'TOP (T)', isDense: true),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('0')),
                                  DropdownMenuItem(value: 1, child: Text('1')),
                                  DropdownMenuItem(value: 2, child: Text('2')),
                                  DropdownMenuItem(value: 3, child: Text('3')),
                                ],
                                onChanged: (v) => setDialogState(() => finding.top = v ?? 0),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: finding.vt,
                          decoration: const InputDecoration(labelText: 'Vestibular Tenderness (VT)', isDense: true),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('0 - None')),
                            DropdownMenuItem(value: 1, child: Text('1 - Mild')),
                            DropdownMenuItem(value: 2, child: Text('2 - Moderate')),
                            DropdownMenuItem(value: 3, child: Text('3 - Severe')),
                          ],
                          onChanged: (v) => setDialogState(() => finding.vt = v ?? 0),
                        ),
                      ],
                      const Divider(),
                      const Text('Periodontal Findings', style: TextStyle(fontWeight: FontWeight.bold)),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mobility (Grade I - III)'),
                        value: finding.mobility,
                        onChanged: (val) => setDialogState(() => finding.mobility = val ?? false),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Gingival Recession'),
                        value: finding.recession,
                        onChanged: (val) => setDialogState(() => finding.recession = val ?? false),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Periodontal Pocket'),
                        value: finding.pocket,
                        onChanged: (val) => setDialogState(() => finding.pocket = val ?? false),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Trauma from Occlusion (TFO)'),
                        value: finding.tfo,
                        onChanged: (val) => setDialogState(() => finding.tfo = val ?? false),
                      ),
                      const Divider(),
                      const Text('Specific Pulpal / Periapical Diagnosis', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: finding.specificDiagnosis,
                        decoration: const InputDecoration(labelText: 'Specific Diagnosis', isDense: true),
                        hint: const Text('Select if applicable'),
                        items: const [
                          DropdownMenuItem(value: 'Normal', child: Text('Normal')),
                          DropdownMenuItem(value: 'Decay', child: Text('Decay / Caries')),
                          DropdownMenuItem(value: 'Pulpitis', child: Text('Pulpitis (Reversible / Irreversible)')),
                          DropdownMenuItem(value: 'Abscess', child: Text('Periapical Abscess')),
                          DropdownMenuItem(value: 'Periodontitis', child: Text('Apical / Marginal Periodontitis')),
                          DropdownMenuItem(value: 'Fracture', child: Text('Crown / Root Fracture')),
                          DropdownMenuItem(value: 'Attrition', child: Text('Severe Attrition')),
                        ],
                        onChanged: (v) => setDialogState(() => finding.specificDiagnosis = v),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    widget.model.setCondition(toothId, selectedCondition);
                    if (selectedCondition == ToothCondition.none || selectedCondition == ToothCondition.missing) {
                      widget.model.toothFindings.remove(toothId);
                    } else if (selectedCondition == ToothCondition.treated) {
                      finding.treatmentType ??= 'restored';
                      widget.model.toothFindings[toothId] = finding;
                    } else if (selectedCondition == ToothCondition.abnormal) {
                      if (!finding.isDecayed &&
                          !finding.isFracture &&
                          !finding.isAttrition &&
                          !finding.isAbrasion &&
                          !finding.isNonVital &&
                          !finding.isAnomalies &&
                          !finding.isRootStump &&
                          !finding.isImpacted &&
                          finding.specificDiagnosis == null) {
                        finding.isDecayed = true;
                        if (finding.decayAreas.isEmpty) finding.decayAreas.add('occlusal');
                      }
                      widget.model.toothFindings[toothId] = finding;
                    }
                  });
                  _syncTuiControllersFromModel();
                  _notifyChange();
                  Navigator.pop(ctx);
                },
                child: const Text('Apply Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportPdf() async {
    await OdontogramPdfService.printOrShare(
      context: context,
      model: widget.model,
      phone: widget.patientPhone,
      appointment: widget.appointment,
      clinic: widget.clinic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final topBar = _buildTopBar();

        if (isWide && widget.isFullScreen) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    _buildAiAssistantCard(),
                    _buildComplaintsCard(),
                  ],
                ),
              ),
              topBar,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(6),
                        child: Column(children: [_buildGuiChartCard(500)]),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          children: [
                            _buildTuiDiagnosisCard(),
                            const SizedBox(height: 6),
                            _buildSummariesCard(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAiAssistantCard(),
              _buildComplaintsCard(),
              const SizedBox(height: 8),
              topBar,
              _buildGuiChartCard(constraints.maxWidth),
              const SizedBox(height: 8),
              _buildTuiDiagnosisCard(),
              const SizedBox(height: 8),
              _buildSummariesCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.grid_view_rounded, size: 18, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
            const Text('Dentition', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final type in DentitionType.values) ...[
                      ChoiceChip(
                        label: Text(type.displayName, style: const TextStyle(fontSize: 11)),
                        selected: widget.model.dentition == type,
                        visualDensity: VisualDensity.compact,
                        onSelected: widget.isReadOnly
                            ? null
                            : (selected) {
                                if (!selected) return;
                                setState(() => widget.model.dentition = type);
                                _notifyChange();
                              },
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.showPdfExportButton) ...[
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('Export PDF', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGuiChartCard(double maxWidth) {
    final height = (maxWidth * 1.2).clamp(380.0, 560.0);
    final size = Size(maxWidth, height);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.touch_app, size: 18, color: Colors.blue),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'GUI: Visual Dental Arch Chart',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isReadOnly && _selectedTooth != null) ...[
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: () => _openToothDialog(_selectedTooth!),
                    icon: const Icon(Icons.edit_note, size: 14),
                    label: Text('Edit Tooth $_selectedTooth', style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  ),
                ],
              ],
            ),
            const Divider(height: 12),
            _buildLegend(),
            const SizedBox(height: 8),
            GestureDetector(
              onTapUp: (details) => _onCanvasTap(details, size),
              onLongPressEnd: (details) => _onCanvasLongPress(details, size),
              child: CustomPaint(
                size: size,
                painter: OdontogramPainter(
                  model: widget.model,
                  selectedToothId: _selectedTooth,
                  showCalculus: true,
                ),
              ),
            ),
            if (!widget.isReadOnly)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'GUI: Tap tooth to open tooth modal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTuiDiagnosisCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.keyboard, size: 18, color: Colors.indigo),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'TUI: Diagnosis with Editable Tooth Numbers',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Type or edit tooth numbers with keyboard (e.g. 11, 26, 47). Both GUI chart and summaries update live.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            const Divider(height: 14),
            _buildTuiCategoryRow('Decayed', 'Decayed (Caries)', Colors.amber.shade800, hint: 'e.g. 11, 26, 47'),
            _buildTuiCategoryRow('Missing', 'Missing (Extracted)', Colors.black87),
            _buildTuiCategoryRow('Treated', 'Treated (Restored)', Colors.green.shade700),
            _buildTuiCategoryRow('Pulpitis', 'Pulpitis (Pulp Pain)', Colors.pink.shade700),
            _buildTuiCategoryRow('Abscess', 'Periapical Abscess', Colors.deepOrange),
            _buildTuiCategoryRow('Fracture', 'Tooth Fracture', Colors.red.shade700),
            _buildTuiCategoryRow('Periodontitis', 'Periodontitis', Colors.red.shade900),
            _buildTuiCategoryRow('Attrition', 'Severe Attrition', Colors.brown),
            _buildTuiCategoryRow('Root Stump', 'Root Stump', Colors.deepPurple),
            _buildTuiCategoryRow('Impacted', 'Impacted Teeth', Colors.blueGrey),
            _buildTuiCategoryRow('Mobility', 'Tooth Mobility', Colors.amber.shade900),
            _buildTuiCalculusRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildTuiCalculusRow() {
    final hasCalc = widget.model.hasCalculus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: hasCalc ? Colors.amber.shade700 : Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const SizedBox(
            width: 140,
            child: Text('Calculus', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)),
            ),
            segments: const [
              ButtonSegment<bool>(value: false, label: Text('No', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              ButtonSegment<bool>(value: true, label: Text('Yes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            ],
            selected: {hasCalc},
            onSelectionChanged: widget.isReadOnly
                ? null
                : (newSelection) {
                    setState(() => widget.model.hasCalculus = newSelection.first);
                    _syncTuiControllersFromModel();
                    _notifyChange();
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildTuiCategoryRow(String category, String label, Color indicatorColor, {String? hint}) {
    final ctrl = _tuiControllers[category];
    final focusNode = _tuiFocusNodes[category];
    if (ctrl == null) return const SizedBox.shrink();
    final showHint = hint != null && !(focusNode?.hasFocus ?? false);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: indicatorColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: ctrl,
              focusNode: focusNode,
              enabled: !widget.isReadOnly,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: showHint ? hint : null,
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (val) {
                _activeTuiCategory = category;
                _onTuiCategoryChanged(category, val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _buildLegendItem(const Color(0xFFE2E8F0), 'Normal', border: Colors.black54),
        _buildLegendItem(const Color(0xFFEF4444), 'Abnormal / Pulpitis / Abscess'),
        _buildLegendItem(const Color(0xFFFEF08A), 'Decay / Caries', border: const Color(0xFFDC2626)),
        _buildLegendItem(const Color(0xFF1F2937), 'Missing (Extracted)'),
        _buildLegendItem(const Color(0xFF22C55E), 'Treated'),
        _buildLegendItem(const Color(0xFFF59E0B), 'Calculus'),
      ],
    );
  }

  Widget _buildComplaintsCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: _showComplaintsSection,
        onExpansionChanged: (v) => setState(() => _showComplaintsSection = v),
        title: const Text('Chief Complaints', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(
          widget.model.complaints.isEmpty ? 'No complaints recorded' : '${widget.model.complaints.length} complaint(s) recorded',
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ...widget.model.complaints.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final c = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Text('${idx + 1}. ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Expanded(flex: 2, child: Text('Type: ${c.type}', style: const TextStyle(fontSize: 12))),
                        Expanded(flex: 1, child: Text('Tooth: ${c.toothId}', style: const TextStyle(fontSize: 12))),
                        Expanded(flex: 2, child: Text('Since: ${c.duration}', style: const TextStyle(fontSize: 12))),
                        if (!widget.isReadOnly)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                            onPressed: () {
                              setState(() => widget.model.complaints.removeAt(idx));
                              _notifyChange();
                            },
                          ),
                      ],
                    ),
                  );
                }),
                if (!widget.isReadOnly && widget.model.complaints.length < 3)
                  OutlinedButton.icon(
                    onPressed: () => _addComplaintDialog(),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add Chief Complaint', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummariesCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text('Clinical Findings & Live Summaries',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ),
                Chip(
                  label: Text('DMFT: ${widget.model.dmftIndex}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  backgroundColor: Colors.amber.shade100,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Kennedy Classification: ${widget.model.kennedyClassification}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo)),
            const Divider(height: 16),
            const Text('Tooth Conditions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            _buildSummaryLine('Abnormal', widget.model.abnormalTeeth.isEmpty ? 'None' : widget.model.abnormalTeeth.join(', '), color: Colors.red),
            _buildSummaryLine('Missing', widget.model.missingTeeth.isEmpty ? 'None' : widget.model.missingTeeth.join(', '), color: Colors.black87),
            _buildSummaryLine('Treated', widget.model.treatedTeeth.isEmpty ? 'None' : widget.model.treatedTeeth.join(', '), color: Colors.green),
            const Divider(height: 16),
            const Text('Diagnosis Summary:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Text(widget.model.toDiagnosisSummaryString(), style: const TextStyle(fontSize: 12, height: 1.3)),
            const Divider(height: 16),
            const Text('Treatment Plan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Text(widget.model.toTreatmentPlanSummaryString(), style: const TextStyle(fontSize: 12, height: 1.3, color: Colors.teal)),
          ],
        ),
      ),
    );
  }

  void _addComplaintDialog() {
    final typeCtrl = TextEditingController(text: 'Pain');
    final toothCtrl = TextEditingController(text: _selectedTooth ?? '11');
    final durationCtrl = TextEditingController(text: '3 days ago');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Chief Complaint'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Complaint Type (e.g. Pain, Sensitivity)')),
            TextField(controller: toothCtrl, decoration: const InputDecoration(labelText: 'Tooth Number (FDI)')),
            TextField(controller: durationCtrl, decoration: const InputDecoration(labelText: 'Duration / Since (e.g. 2 days ago)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (typeCtrl.text.isNotEmpty && toothCtrl.text.isNotEmpty) {
                widget.model.complaints.add(ChiefComplaint(
                  type: typeCtrl.text.trim(),
                  toothId: toothCtrl.text.trim(),
                  duration: durationCtrl.text.trim(),
                ));
                Navigator.pop(ctx);
                _notifyChange();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, {Color? border}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: border != null ? Border.all(color: border, width: 1.5) : null,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildSummaryLine(String title, String content, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            TextSpan(text: '$title: ', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            TextSpan(text: content),
          ],
        ),
      ),
    );
  }
}
