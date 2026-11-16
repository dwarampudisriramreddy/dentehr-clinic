import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kTreatmentTeal = Color(0xFF0D9488);
const Color kTreatmentNavy = Color(0xFF1E3A5F);
const String kClinicName = 'Dentehr Clinic';

class TreatmentScreen extends StatefulWidget {
  const TreatmentScreen({super.key});

  @override
  State<TreatmentScreen> createState() => _TreatmentScreenState();
}

class _TreatmentScreenState extends State<TreatmentScreen> {
  List<Map<String, dynamic>> _treatments = [];
  List<Map<String, dynamic>> _overrides = [];
  bool _loading = false;
  String? _loadError;
  String? _overrideError;
  String _searchQuery = '';
  String _categoryFilter = 'All';
  String _availabilityFilter = 'All';

  static const List<String> _categories = [
    'All',
    'Diagnostic',
    'Preventive',
    'Restorative',
    'Endodontic',
    'Surgical',
    'Prosthodontic',
    'Implantology',
    'Cosmetic',
    'Periodontic',
    'Orthodontic',
  ];
  static const List<String> _availabilityValues = ['available', 'limited', 'unavailable'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final treatments = await Supabase.instance.client
          .from('treatments')
          .select()
          .order('category');

      List<Map<String, dynamic>> overrides = [];
      String? overrideError;
      try {
        final rows = await Supabase.instance.client
            .from('clinic_treatments')
            .select()
            .eq('clinic', kClinicName);
        overrides = List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        overrideError = 'Clinic pricing is not set up yet. Showing and editing global defaults.';
      }

      if (!mounted) return;
      setState(() {
        _treatments = List<Map<String, dynamic>>.from(treatments);
        _overrides = overrides;
        _overrideError = overrideError;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  Map<String, dynamic>? _overrideFor(Object? treatmentId) {
    for (final override in _overrides) {
      if (override['treatment_id']?.toString() == treatmentId?.toString()) {
        return override;
      }
    }
    return null;
  }

  String _normalizeAvailability(Object? value) {
    return (value ?? 'available').toString().toLowerCase();
  }

  String _availabilityLabel(String value) {
    if (value.isEmpty) return 'Unknown';
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  Color _availabilityColor(String availability) {
    switch (availability) {
      case 'available':
        return Colors.green;
      case 'limited':
        return Colors.amber.shade800;
      case 'unavailable':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _searchQuery.toLowerCase();
    return _treatments.where((treatment) {
      final category = (treatment['category'] ?? '').toString();
      final override = _overrideFor(treatment['id']);
      final availability = _normalizeAvailability(
        override?['availability'] ?? treatment['availability'],
      );
      final name = (treatment['name'] ?? '').toString().toLowerCase();
      final description = (treatment['description'] ?? '').toString().toLowerCase();

      if (_categoryFilter != 'All' && category != _categoryFilter) return false;
      if (_availabilityFilter != 'All' && availability != _availabilityFilter) return false;
      if (query.isNotEmpty && !name.contains(query) && !description.contains(query)) return false;
      return true;
    }).toList();
  }

  Future<void> _editTreatment(Map<String, dynamic> treatment) async {
    final override = _overrideFor(treatment['id']);
    final costCtrl = TextEditingController(
      text: ((override?['cost'] as num?)?.toDouble() ??
              (treatment['cost'] as num?)?.toDouble() ??
              0)
          .toStringAsFixed(2),
    );
    String availability = _normalizeAvailability(
      override?['availability'] ?? treatment['availability'],
    );
    bool isActive = (override?['is_active'] ?? treatment['is_active'] ?? true) == true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit ${treatment['name']}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: availability,
                    decoration: const InputDecoration(
                      labelText: 'Availability',
                      border: OutlineInputBorder(),
                    ),
                    items: _availabilityValues
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_availabilityLabel(value)),
                            ))
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => availability = value ?? availability,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: costCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Cost',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Available at this clinic'),
                    value: isActive,
                    onChanged: (value) => setDialogState(() => isActive = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;

    final cost = double.tryParse(costCtrl.text.trim()) ?? 0;
    try {
      if (_overrideError == null) {
        await Supabase.instance.client.from('clinic_treatments').upsert({
          'clinic': kClinicName,
          'treatment_id': treatment['id'],
          'cost': cost,
          'availability': availability,
          'is_active': isActive,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'clinic,treatment_id');
      } else {
        await Supabase.instance.client.from('treatments').update({
          'cost': cost,
          'availability': availability,
          'is_active': isActive,
        }).eq('id', treatment['id']);
      }
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating treatment: $error'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Treatments'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search treatments...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Unable to load treatments:\n$_loadError', textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    if (_overrideError != null)
                      Container(
                        width: double.infinity,
                        color: Colors.amber.shade100,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _overrideError!,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _categoryFilter,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: _categories
                                  .map((category) => DropdownMenuItem(
                                        value: category,
                                        child: Text(category),
                                      ))
                                  .toList(),
                              onChanged: (value) => setState(
                                () => _categoryFilter = value ?? 'All',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _availabilityFilter,
                              decoration: const InputDecoration(
                                labelText: 'Availability',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(value: 'All', child: Text('All')),
                                ..._availabilityValues.map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(_availabilityLabel(value)),
                                  ),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => _availabilityFilter = value ?? 'All',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? const Center(child: Text('No treatments found'))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: _filtered.length,
                              itemBuilder: (_, index) {
                                final treatment = _filtered[index];
                                final override = _overrideFor(treatment['id']);
                                final name = (treatment['name'] ?? '').toString();
                                final category = (treatment['category'] ?? '').toString();
                                final availability = _normalizeAvailability(
                                  override?['availability'] ?? treatment['availability'],
                                );
                                final cost = (override?['cost'] as num?)?.toDouble() ??
                                    (treatment['cost'] as num?)?.toDouble() ??
                                    0;
                                final duration = treatment['duration_minutes'];
                                final description = (treatment['description'] ?? '').toString();
                                final isActive =
                                    (override?['is_active'] ?? treatment['is_active'] ?? true) == true;
                                final color = _availabilityColor(availability);

                                if (!isActive) return const SizedBox.shrink();

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          margin: const EdgeInsets.only(top: 5),
                                          decoration: BoxDecoration(
                                            color: color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                description.isEmpty
                                                    ? category
                                                    : '$category • $description',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 10,
                                                runSpacing: 6,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: color.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(color: color),
                                                    ),
                                                    child: Text(
                                                      _availabilityLabel(availability),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: color,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    'Cost: \$${cost.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: kTreatmentNavy,
                                                    ),
                                                  ),
                                                  if (duration != null)
                                                    Text(
                                                      '$duration min',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey.shade600,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: kTreatmentTeal),
                                          tooltip: 'Adjust cost & availability',
                                          onPressed: () => _editTreatment(treatment),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
