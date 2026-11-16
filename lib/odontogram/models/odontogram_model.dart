import 'dart:convert';

enum ToothCondition {
  none, // Normal
  abnormal, // Needs treatment/attention
  missing, // Extracted/missing
  treated, // Already treated
}

enum DentitionType {
  permanent,
  mixed,
  primary,
  edentulous;

  String get displayName {
    switch (this) {
      case DentitionType.permanent:
        return 'Permanent';
      case DentitionType.mixed:
        return 'Mixed';
      case DentitionType.primary:
        return 'Primary';
      case DentitionType.edentulous:
        return 'Edentulous';
    }
  }
}

class ToothFinding {
  bool isDecayed;
  List<String> decayAreas; // occlusal, buccal, mesial, distal, lingual
  bool isFracture;
  bool isAttrition;
  bool isAbrasion;
  bool isNonVital;
  bool isAnomalies;
  bool isRootStump;
  bool isImpacted;

  int pain; // 0, 1, 2
  int top; // 0, 1, 2, 3
  int vt; // 0, 1, 2, 3

  bool mobility;
  bool recession;
  bool pocket;
  bool tfo;

  String? specificDiagnosis; // Decay, Pulpitis, Abscess, Periodontitis, Fracture, Attrition, Normal

  // Treatment options (for treated teeth or planned treatments)
  String? treatmentType; // implant, fpd, filled, restored
  bool hasFailure;

  ToothFinding({
    this.isDecayed = false,
    List<String>? decayAreas,
    this.isFracture = false,
    this.isAttrition = false,
    this.isAbrasion = false,
    this.isNonVital = false,
    this.isAnomalies = false,
    this.isRootStump = false,
    this.isImpacted = false,
    this.pain = 0,
    this.top = 0,
    this.vt = 0,
    this.mobility = false,
    this.recession = false,
    this.pocket = false,
    this.tfo = false,
    this.specificDiagnosis,
    this.treatmentType,
    this.hasFailure = false,
  }) : decayAreas = decayAreas ?? [];

  Map<String, dynamic> toJson() => {
        'isDecayed': isDecayed,
        'decayAreas': decayAreas,
        'isFracture': isFracture,
        'isAttrition': isAttrition,
        'isAbrasion': isAbrasion,
        'isNonVital': isNonVital,
        'isAnomalies': isAnomalies,
        'isRootStump': isRootStump,
        'isImpacted': isImpacted,
        'pain': pain,
        'top': top,
        'vt': vt,
        'mobility': mobility,
        'recession': recession,
        'pocket': pocket,
        'tfo': tfo,
        'specificDiagnosis': specificDiagnosis,
        'treatmentType': treatmentType,
        'hasFailure': hasFailure,
      };

  factory ToothFinding.fromJson(Map<String, dynamic> json) => ToothFinding(
        isDecayed: json['isDecayed'] ?? false,
        decayAreas: List<String>.from(json['decayAreas'] ?? []),
        isFracture: json['isFracture'] ?? false,
        isAttrition: json['isAttrition'] ?? false,
        isAbrasion: json['isAbrasion'] ?? false,
        isNonVital: json['isNonVital'] ?? false,
        isAnomalies: json['isAnomalies'] ?? false,
        isRootStump: json['isRootStump'] ?? false,
        isImpacted: json['isImpacted'] ?? false,
        pain: json['pain'] ?? 0,
        top: json['top'] ?? 0,
        vt: json['vt'] ?? 0,
        mobility: json['mobility'] ?? false,
        recession: json['recession'] ?? false,
        pocket: json['pocket'] ?? false,
        tfo: json['tfo'] ?? false,
        specificDiagnosis: json['specificDiagnosis'],
        treatmentType: json['treatmentType'],
        hasFailure: json['hasFailure'] ?? false,
      );

  ToothFinding clone() => ToothFinding(
        isDecayed: isDecayed,
        decayAreas: List<String>.from(decayAreas),
        isFracture: isFracture,
        isAttrition: isAttrition,
        isAbrasion: isAbrasion,
        isNonVital: isNonVital,
        isAnomalies: isAnomalies,
        isRootStump: isRootStump,
        isImpacted: isImpacted,
        pain: pain,
        top: top,
        vt: vt,
        mobility: mobility,
        recession: recession,
        pocket: pocket,
        tfo: tfo,
        specificDiagnosis: specificDiagnosis,
        treatmentType: treatmentType,
        hasFailure: hasFailure,
      );
}

class ChiefComplaint {
  String type;
  String toothId;
  String duration;

  ChiefComplaint({
    required this.type,
    required this.toothId,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'toothId': toothId,
        'duration': duration,
      };

  factory ChiefComplaint.fromJson(Map<String, dynamic> json) => ChiefComplaint(
        type: json['type'] ?? '',
        toothId: json['toothId'] ?? '',
        duration: json['duration'] ?? '',
      );
}

class OdontogramModel {
  DentitionType dentition;
  final Map<String, ToothCondition> toothStates;
  final Map<String, ToothFinding> toothFindings;
  bool hasCalculus;
  final List<ChiefComplaint> complaints;

  Set<String> get calculusSegments => hasCalculus ? {'calculus'} : {};

  static const List<String> permanentTeeth = [
    '18', '17', '16', '15', '14', '13', '12', '11',
    '21', '22', '23', '24', '25', '26', '27', '28',
    '48', '47', '46', '45', '44', '43', '42', '41',
    '31', '32', '33', '34', '35', '36', '37', '38',
  ];

  static const List<String> primaryTeeth = [
    '55', '54', '53', '52', '51',
    '61', '62', '63', '64', '65',
    '85', '84', '83', '82', '81',
    '71', '72', '73', '74', '75',
  ];

  static const List<String> allTeeth = [
    '18', '17', '16', '15', '14', '13', '12', '11',
    '21', '22', '23', '24', '25', '26', '27', '28',
    '31', '32', '33', '34', '35', '36', '37', '38',
    '41', '42', '43', '44', '45', '46', '47', '48',
    '51', '52', '53', '54', '55',
    '61', '62', '63', '64', '65',
    '71', '72', '73', '74', '75',
    '81', '82', '83', '84', '85',
  ];

  OdontogramModel({
    this.dentition = DentitionType.permanent,
    Map<String, ToothCondition>? toothStates,
    Map<String, ToothFinding>? toothFindings,
    this.hasCalculus = false,
    Set<String>? calculusSegments,
    List<ChiefComplaint>? complaints,
  })  : toothStates = toothStates ?? {},
        toothFindings = toothFindings ?? {},
        complaints = complaints ?? [] {
    if (calculusSegments != null && calculusSegments.isNotEmpty) {
      hasCalculus = true;
    }
  }

  List<String> get visibleTeeth {
    switch (dentition) {
      case DentitionType.permanent:
        return permanentTeeth;
      case DentitionType.primary:
        return primaryTeeth;
      case DentitionType.mixed:
        return [...permanentTeeth, ...primaryTeeth];
      case DentitionType.edentulous:
        return const [];
    }
  }

  ToothCondition getCondition(String toothId) =>
      toothStates[toothId] ?? ToothCondition.none;

  ToothFinding getFinding(String toothId) =>
      toothFindings.putIfAbsent(toothId, () => ToothFinding());

  void setCondition(String toothId, ToothCondition condition) {
    if (condition == ToothCondition.none) {
      toothStates.remove(toothId);
    } else {
      toothStates[toothId] = condition;
    }
  }

  void cycleToothCondition(String toothId) {
    final current = getCondition(toothId);
    ToothCondition next;
    switch (current) {
      case ToothCondition.none:
        next = ToothCondition.abnormal;
        break;
      case ToothCondition.abnormal:
        next = ToothCondition.missing;
        break;
      case ToothCondition.missing:
        next = ToothCondition.treated;
        break;
      case ToothCondition.treated:
        next = ToothCondition.none;
        break;
    }
    setCondition(toothId, next);
  }

  // --- Classification & Calculations ---

  int get dmftIndex {
    final abnormal = toothStates.values.where((c) => c == ToothCondition.abnormal).length;
    final missing = toothStates.values.where((c) => c == ToothCondition.missing).length;
    final treated = toothStates.values.where((c) => c == ToothCondition.treated).length;
    return abnormal + missing + treated;
  }

  String get kennedyClassification {
    final missing = toothStates.entries
        .where((e) => e.value == ToothCondition.missing)
        .map((e) => e.key)
        .toList();

    if (missing.isEmpty) return 'No Kennedy Classification';
    if (missing.contains('36') || missing.contains('46')) return 'Class I';
    if (missing.contains('37') || missing.contains('47')) return 'Class II';
    return 'Class III or IV';
  }

  String get periodontalDiagnosis {
    final mobilityTeeth = toothFindings.entries
        .where((e) => e.value.mobility)
        .map((e) => e.key)
        .toList();

    if (mobilityTeeth.length > 1) {
      return 'Generalized Periodontitis';
    } else if (mobilityTeeth.length == 1) {
      return 'Localized Periodontitis (Tooth ${mobilityTeeth.first})';
    }
    return 'Normal / None';
  }

  // Caries classification logic matching odontogram.html
  static const List<List<String>> _class1Combinations = [
    ['occlusal'],
    ['buccal'],
    ['lingual'],
    ['occlusal', 'buccal'],
    ['occlusal', 'lingual'],
  ];

  static const List<List<String>> _class2Combinations = [
    ['mesial'],
    ['distal'],
    ['mesial', 'occlusal'],
    ['distal', 'occlusal'],
    ['mesial', 'occlusal', 'distal'],
    ['mesial', 'occlusal', 'distal', 'buccal'],
    ['mesial', 'occlusal', 'distal', 'buccal', 'lingual'],
  ];

  static const List<String> _areaOrder = [
    'mesial',
    'occlusal',
    'distal',
    'buccal',
    'lingual',
  ];

  static String sortAreas(List<String> areas) {
    final sorted = List<String>.from(areas);
    sorted.sort((a, b) => _areaOrder.indexOf(a).compareTo(_areaOrder.indexOf(b)));
    return sorted.join('-');
  }

  static bool _setEqualsUnordered(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final setB = b.toSet();
    return a.every(setB.contains);
  }

  static ({String diagnosis, String treatment}) evaluateCaries(List<String> areas) {
    if (areas.isEmpty) {
      return (diagnosis: 'Dental Caries', treatment: 'Restoration');
    }
    for (final c in _class1Combinations) {
      if (_setEqualsUnordered(c, areas)) {
        return (
          diagnosis: 'Pit and fissure caries',
          treatment: '${sortAreas(areas)} Class 1 restoration'
        );
      }
    }
    for (final c in _class2Combinations) {
      if (_setEqualsUnordered(c, areas)) {
        return (
          diagnosis: 'Proximal caries',
          treatment: '${sortAreas(areas)} Class 2 restoration'
        );
      }
    }
    return (
      diagnosis: 'Multiple caries',
      treatment: '${sortAreas(areas)} Complex restoration'
    );
  }

  // --- Summaries ---

  List<String> get abnormalTeeth => toothStates.entries
      .where((e) => e.value == ToothCondition.abnormal)
      .map((e) => e.key)
      .toList();

  List<String> get missingTeeth => toothStates.entries
      .where((e) => e.value == ToothCondition.missing)
      .map((e) => e.key)
      .toList();

  List<String> get treatedTeeth => toothStates.entries
      .where((e) => e.value == ToothCondition.treated)
      .map((e) => e.key)
      .toList();

  /// Extract valid 2-digit FDI tooth numbers from string input
  static Set<String> parseToothNumbers(String input) {
    return RegExp(r'\b(1[1-8]|2[1-8]|3[1-8]|4[1-8]|5[1-5]|6[1-5]|7[1-5]|8[1-5])\b')
        .allMatches(input)
        .map((m) => m.group(0)!)
        .toSet();
  }

  /// Get comma-separated list of teeth for a specific diagnosis / state (for TUI)
  String getTeethStringForCategory(String category) {
    switch (category) {
      case 'Missing':
        return missingTeeth.join(', ');
      case 'Treated':
        return treatedTeeth.join(', ');
      case 'Mobility':
        return toothFindings.entries.where((e) => e.value.mobility).map((e) => e.key).join(', ');
      case 'Recession':
        return toothFindings.entries.where((e) => e.value.recession).map((e) => e.key).join(', ');
      case 'Pocket':
        return toothFindings.entries.where((e) => e.value.pocket).map((e) => e.key).join(', ');
      case 'Calculus':
        return hasCalculus ? 'Yes' : 'No';
      default:
        return (diagnosisTeethMap[category] ?? []).join(', ');
    }
  }

  /// Update teeth conditions from a keyboard text input of tooth numbers (for TUI)
  void setTeethForCategory(String category, String input) {
    if (category == 'Calculus') {
      final s = input.trim().toLowerCase();
      hasCalculus = s == 'yes' || s == 'y' || s == 'true' || s == '1' || s == 'present';
      return;
    }

    final newTeeth = parseToothNumbers(input);

    if (category == 'Missing') {
      for (final tid in List<String>.from(missingTeeth)) {
        if (!newTeeth.contains(tid)) {
          setCondition(tid, ToothCondition.none);
        }
      }
      for (final tid in newTeeth) {
        setCondition(tid, ToothCondition.missing);
      }
      return;
    }

    if (category == 'Treated') {
      for (final tid in List<String>.from(treatedTeeth)) {
        if (!newTeeth.contains(tid)) {
          setCondition(tid, ToothCondition.none);
        }
      }
      for (final tid in newTeeth) {
        setCondition(tid, ToothCondition.treated);
        getFinding(tid).treatmentType ??= 'restored';
      }
      return;
    }

    if (category == 'Mobility') {
      for (final entry in toothFindings.entries) {
        entry.value.mobility = newTeeth.contains(entry.key);
      }
      for (final tid in newTeeth) {
        getFinding(tid).mobility = true;
      }
      return;
    }

    if (category == 'Recession') {
      for (final entry in toothFindings.entries) {
        entry.value.recession = newTeeth.contains(entry.key);
      }
      for (final tid in newTeeth) {
        getFinding(tid).recession = true;
      }
      return;
    }

    if (category == 'Pocket') {
      for (final entry in toothFindings.entries) {
        entry.value.pocket = newTeeth.contains(entry.key);
      }
      for (final tid in newTeeth) {
        getFinding(tid).pocket = true;
      }
      return;
    }

    // Diagnosis categories
    final currentCategoryTeeth = List<String>.from(diagnosisTeethMap[category] ?? []);
    for (final tid in currentCategoryTeeth) {
      if (!newTeeth.contains(tid)) {
        final f = toothFindings[tid];
        if (f != null) {
          if (category == 'Decayed') f.isDecayed = false;
          if (category == 'Fracture') f.isFracture = false;
          if (category == 'Attrition') f.isAttrition = false;
          if (category == 'Abrasion') f.isAbrasion = false;
          if (category == 'Root Stump') f.isRootStump = false;
          if (category == 'Impacted') f.isImpacted = false;
          if (f.specificDiagnosis == category) f.specificDiagnosis = null;

          if (!f.isDecayed &&
              !f.isFracture &&
              !f.isAttrition &&
              !f.isAbrasion &&
              !f.isRootStump &&
              !f.isImpacted &&
              f.specificDiagnosis == null) {
            setCondition(tid, ToothCondition.none);
          }
        }
      }
    }

    for (final tid in newTeeth) {
      setCondition(tid, ToothCondition.abnormal);
      final f = getFinding(tid);
      if (category == 'Decayed') {
        f.isDecayed = true;
        if (f.decayAreas.isEmpty) f.decayAreas.add('occlusal');
      } else if (category == 'Fracture') {
        f.isFracture = true;
      } else if (category == 'Attrition') {
        f.isAttrition = true;
      } else if (category == 'Abrasion') {
        f.isAbrasion = true;
      } else if (category == 'Root Stump') {
        f.isRootStump = true;
      } else if (category == 'Impacted') {
        f.isImpacted = true;
      } else {
        f.specificDiagnosis = category;
      }
    }
  }

  Map<String, List<String>> get diagnosisTeethMap {
    final map = <String, List<String>>{
      'Decayed': [],
      'Fracture': [],
      'Pulpitis': [],
      'Abscess': [],
      'Periodontitis': [],
      'Attrition': [],
      'Abrasion': [],
      'Root Stump': [],
      'Impacted': [],
      'Normal': [],
    };

    for (final tid in abnormalTeeth) {
      final f = toothFindings[tid];
      if (f == null) {
        map['Decayed']!.add(tid);
        continue;
      }
      if (f.specificDiagnosis != null && map.containsKey(f.specificDiagnosis)) {
        map[f.specificDiagnosis]!.add(tid);
      } else {
        if (f.isDecayed) map['Decayed']!.add(tid);
        if (f.isFracture) map['Fracture']!.add(tid);
        if (f.isAttrition) map['Attrition']!.add(tid);
        if (f.isAbrasion) map['Abrasion']!.add(tid);
        if (f.isRootStump) map['Root Stump']!.add(tid);
        if (f.isImpacted) map['Impacted']!.add(tid);
        if (!f.isDecayed &&
            !f.isFracture &&
            !f.isAttrition &&
            !f.isAbrasion &&
            !f.isRootStump &&
            !f.isImpacted) {
          map['Decayed']!.add(tid);
        }
      }
    }

    return map;
  }

  Map<String, List<String>> get treatmentTeethMap {
    final map = <String, List<String>>{
      'Restoration': [],
      'Root Canal': [],
      'Extraction': [],
      'Implant': [],
      'FPD': [],
      'Filled': [],
    };

    // Abnormal teeth treatment derivation
    for (final tid in abnormalTeeth) {
      final f = toothFindings[tid];
      if (f == null || f.isDecayed) {
        map['Restoration']!.add(tid);
      } else if (f.specificDiagnosis == 'Pulpitis' || f.specificDiagnosis == 'Periodontitis') {
        map['Root Canal']!.add(tid);
      } else if (f.isFracture || f.isAttrition || f.isRootStump) {
        map['Extraction']!.add(tid);
      } else {
        map['Restoration']!.add(tid);
      }
    }

    // Missing teeth treatment
    for (final tid in missingTeeth) {
      map['Implant']!.add(tid);
    }

    // Treated teeth
    for (final tid in treatedTeeth) {
      final f = toothFindings[tid];
      if (f?.treatmentType == 'implant') map['Implant']!.add(tid);
      if (f?.treatmentType == 'fpd') map['FPD']!.add(tid);
      if (f?.treatmentType == 'filled') map['Filled']!.add(tid);
      if (f?.treatmentType == 'restored') map['Restoration']!.add(tid);
    }

    return map;
  }

  String toDiagnosisSummaryString() {
    final parts = <String>[];
    diagnosisTeethMap.forEach((category, teeth) {
      if (teeth.isNotEmpty) {
        parts.add('$category: ${teeth.join(', ')}');
      }
    });

    final mobility = toothFindings.entries.where((e) => e.value.mobility).map((e) => e.key).toList();
    if (mobility.isNotEmpty) {
      parts.add('Mobility: ${mobility.join(', ')} ($periodontalDiagnosis)');
    }

    if (missingTeeth.isNotEmpty) {
      parts.add('Partially Edentulous: ${missingTeeth.join(', ')} ($kennedyClassification)');
    }

    if (hasCalculus) {
      parts.add('Calculus: Yes');
    }

    if (parts.isEmpty) return 'Oral cavity clinically normal.';
    return parts.join('; ');
  }

  String toTreatmentPlanSummaryString() {
    final parts = <String>[];
    treatmentTeethMap.forEach((category, teeth) {
      if (teeth.isNotEmpty) {
        parts.add('$category: ${teeth.join(', ')}');
      }
    });

    if (parts.isEmpty) return 'Preventive dental hygiene and routine follow-up.';
    return parts.join('; ');
  }

  // --- Serialization ---

  Map<String, dynamic> toJson() => {
        'dentition': dentition.name,
        'toothStates': toothStates.map((k, v) => MapEntry(k, v.name)),
        'toothFindings': toothFindings.map((k, v) => MapEntry(k, v.toJson())),
        'hasCalculus': hasCalculus,
        'calculusSegments': hasCalculus ? ['calculus'] : <String>[],
        'complaints': complaints.map((c) => c.toJson()).toList(),
      };

  factory OdontogramModel.fromJson(Map<String, dynamic> json) {
    final hasCalc = json['hasCalculus'] == true ||
        ((json['calculusSegments'] as List?)?.isNotEmpty ?? false);
    final m = OdontogramModel(
      dentition: DentitionType.values.firstWhere(
        (e) => e.name == json['dentition'],
        orElse: () => DentitionType.permanent,
      ),
      hasCalculus: hasCalc,
      complaints: (json['complaints'] as List<dynamic>?)
              ?.map((c) => ChiefComplaint.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );

    if (json['toothStates'] is Map) {
      (json['toothStates'] as Map).forEach((k, v) {
        final cond = ToothCondition.values.firstWhere(
          (c) => c.name == v,
          orElse: () => ToothCondition.none,
        );
        m.toothStates[k.toString()] = cond;
      });
    }

    if (json['toothFindings'] is Map) {
      (json['toothFindings'] as Map).forEach((k, v) {
        if (v is Map<String, dynamic>) {
          m.toothFindings[k.toString()] = ToothFinding.fromJson(v);
        }
      });
    }

    return m;
  }

  static const String jsonMarker = '<!--ODONTOGRAM_DATA:';

  /// Serializes into a string safe for DB storage in treatment_plan or diagnosis
  String embedInString(String text) {
    final jsonStr = jsonEncode(toJson());
    return '$text\n$jsonMarker$jsonStr-->';
  }

  /// Parses OdontogramModel from patient database record
  static OdontogramModel fromPatientRecord(Map<String, dynamic> row) {
    final treatmentStr = row['treatment_plan']?.toString() ?? '';
    final diagnosisStr = row['diagnosis']?.toString() ?? '';

    for (final str in [treatmentStr, diagnosisStr]) {
      if (str.contains(jsonMarker)) {
        try {
          final start = str.indexOf(jsonMarker) + jsonMarker.length;
          final end = str.indexOf('-->', start);
          if (end > start) {
            final jsonStr = str.substring(start, end).trim();
            final json = jsonDecode(jsonStr);
            return OdontogramModel.fromJson(json);
          }
        } catch (_) {}
      }
    }

    // Fallback: try parsing tooth numbers from raw strings if no marker found
    final model = OdontogramModel();
    _extractTeethFromText(diagnosisStr, model);
    return model;
  }

  /// Helper to clean string for pure human display without raw JSON marker
  static String cleanDisplayText(String? text) {
    if (text == null) return '';
    final idx = text.indexOf(jsonMarker);
    if (idx != -1) {
      return text.substring(0, idx).trim();
    }
    return text.trim();
  }

  static void _extractTeethFromText(String text, OdontogramModel model) {
    final matches = RegExp(r'\b(1[1-8]|2[1-8]|3[1-8]|4[1-8]|5[1-5]|6[1-5]|7[1-5]|8[1-5])\b')
        .allMatches(text);
    for (final m in matches) {
      final tooth = m.group(0)!;
      model.setCondition(tooth, ToothCondition.abnormal);
    }
  }

  OdontogramModel clone() {
    return OdontogramModel.fromJson(toJson());
  }
}
