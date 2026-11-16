class DefensibleCodingEngine {
  String determineCdtCode(Map<String, dynamic> facts) {
    if (facts.containsKey('error')) return 'MANUAL_REVIEW_REQUIRED';

    final tooth = int.tryParse(facts['tooth']?.toString() ?? '') ?? 0;
    final surface = (facts['surface'] ?? '').toString().toUpperCase();
    final material = (facts['material'] ?? '').toString().toLowerCase();

    final isPosterior = (tooth >= 14 && tooth <= 18) ||
        (tooth >= 24 && tooth <= 28) ||
        (tooth >= 34 && tooth <= 38) ||
        (tooth >= 44 && tooth <= 48);

    if (material.contains('composite')) {
      final s = surface.replaceAll(RegExp(r'[^MODBLIF]'), '');
      final count = s.length;
      if (isPosterior) {
        if (count <= 1) return 'D2391';
        if (count == 2) return 'D2392';
        if (count >= 3) return 'D2393';
      } else {
        if (count <= 1) return 'D2330';
        if (count == 2) return 'D2331';
        if (count == 3) return 'D2332';
        if (count >= 4) return 'D2335';
      }
    }

    return 'UNKNOWN_CODE';
  }

  bool isDefensible(String suggestedCode, {required bool aiConfirmedDecay}) {
    if (suggestedCode.startsWith('D239') && !aiConfirmedDecay) {
      return false;
    }
    return true;
  }
}
