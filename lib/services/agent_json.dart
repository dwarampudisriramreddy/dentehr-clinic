/// Best-effort recovery of an agent response when the model emits invalid JSON.
///
/// Small on-device models often drop commas/colons. When strict JSON decoding
/// fails we still want to recover the action, reply, per-patient changes and
/// names so the clinic app can save findings instead of only echoing raw text.
Map<String, dynamic> salvageAgentJson(String rawText) {
  var text = rawText.replaceAll('```json', '').replaceAll('```', '').trim();
  final result = <String, dynamic>{};

  final action = RegExp(r'"action"\s*[:.]?\s*"([^"]+)"').firstMatch(text)?.group(1);
  if (action != null && action.trim().isNotEmpty) result['action'] = action.trim();

  final reply = RegExp(r'"reply"\s*[:.]?\s*"([\s\S]*?)"\s*,\s*"?(?:query|patients)"?')
      .firstMatch(text)
      ?.group(1);
  if (reply != null) {
    result['reply'] = reply
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\"', '"')
        .trim();
  }

  final chunks = <String>[];
  final parts = text.split(RegExp(r'"patient"\s*[:.]?\s*\{'));
  for (var i = 1; i < parts.length; i++) {
    chunks.add(parts[i]);
  }
  if (chunks.isEmpty) chunks.add(text);

  final toothCategory = RegExp(
    r'"?tooth"?\s*[:.]?\s*"?(\d{1,2})"?[\s\S]{0,50}?"?category"?\s*[:.]?\s*"?([A-Za-z][A-Za-z ]*?)"?\s*[},]',
    caseSensitive: false,
  );

  final patients = <Map<String, dynamic>>[];
  for (final chunk in chunks) {
    final firstName = RegExp(r'"first_name"\s*[:.]?\s*"([^"]*)"')
            .firstMatch(chunk)
            ?.group(1)
            ?.trim() ??
        '';
    final lastName = RegExp(r'"last_name"\s*[:.]?\s*"([^"]*)"')
            .firstMatch(chunk)
            ?.group(1)
            ?.trim() ??
        '';
    final phone = RegExp(r'"phone"\s*[:.]?\s*"([^"]*)"')
            .firstMatch(chunk)
            ?.group(1)
            ?.trim() ??
        '';

    final changes = <Map<String, String>>[];
    for (final m in toothCategory.allMatches(chunk)) {
      final tooth = m.group(1) ?? '';
      final category = (m.group(2) ?? '').trim();
      if (RegExp(r'^(1[1-8]|2[1-8]|3[1-8]|4[1-8])$').hasMatch(tooth) &&
          category.isNotEmpty) {
        changes.add({'tooth': tooth, 'category': category});
      }
    }

    if (changes.isEmpty && firstName.isEmpty && phone.isEmpty) continue;
    patients.add({
      'patient': {
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
      },
      'changes': changes,
    });
  }

  if (patients.isNotEmpty) result['patients'] = patients;
  return result;
}
