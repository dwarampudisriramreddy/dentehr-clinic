import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kVisitListTeal = Color(0xFF0D9488);
const Color kVisitListNavy = Color(0xFF1E3A5F);

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key});

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  List<Map<String, dynamic>> _visits = [];
  bool _loading = false;
  String? _error;
  String _searchQuery = '';
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadVisits();
  }

  Future<void> _loadVisits() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('visits')
          .select()
          .order('visit_date', ascending: false)
          .limit(300);
      if (!mounted) return;
      setState(() {
        _visits = List<Map<String, dynamic>>.from(rows);
      });
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      setState(() {
        _error = message.contains('visits')
            ? 'The visits table was not found. Run supabase/visits.sql in the Supabase SQL Editor, then refresh.\n\n$message'
            : message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _searchQuery.toLowerCase().trim();
    return _visits.where((visit) {
      final status = (visit['payment_status'] ?? 'unpaid').toString();
      if (_statusFilter != 'All' && status != _statusFilter) return false;
      if (query.isEmpty) return true;
      final name = (visit['patient_name'] ?? '').toString().toLowerCase();
      final phone = (visit['patient_phone'] ?? '').toString().toLowerCase();
      final diagnosis = (visit['final_diagnosis'] ?? '').toString().toLowerCase();
      return name.contains(query) || phone.contains(query) || diagnosis.contains(query);
    }).toList();
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0;

  double get _totalCollected =>
      _visits.fold(0, (sum, visit) => sum + _toDouble(visit['amount_paid']));

  double get _totalOutstanding => _visits.fold(
        0,
        (sum, visit) =>
            sum +
            (_toDouble(visit['total']) - _toDouble(visit['amount_paid'])).clamp(0, double.infinity).toDouble(),
      );

  List<Map<String, dynamic>> _treatmentItems(Map<String, dynamic> visit) {
    final raw = visit['treatment_plan'];
    dynamic decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        decoded = <dynamic>[];
      }
    }
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return [];
  }

  Map<String, dynamic> _xray(Map<String, dynamic> visit) {
    final raw = visit['xray'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse('${value ?? ''}')?.toLocal();
    if (date == null) return 'Unknown date';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.day} ${months[date.month - 1]} ${date.year} · $hour:$minute $period';
  }

  String _money(double value) => 'Rs ${value.toStringAsFixed(0)}';

  Future<void> _openVisit(Map<String, dynamic> visit) async {
    final items = _treatmentItems(visit);
    final xray = _xray(visit);
    final total = _toDouble(visit['total']);
    final paid = _toDouble(visit['amount_paid']);
    final balance = (total - paid).clamp(0, double.infinity).toDouble();
    final status = (visit['payment_status'] ?? 'unpaid').toString();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${visit['patient_name'] ?? 'Patient'} · ${_formatDate(visit['visit_date'])}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: Icon(Icons.phone_outlined, size: 16, color: kVisitListNavy),
                      label: Text('${visit['patient_phone'] ?? ''}'),
                    ),
                    Chip(
                      avatar: Icon(Icons.local_hospital_outlined, size: 16, color: kVisitListNavy),
                      label: Text('${visit['clinic'] ?? ''}'),
                    ),
                    Chip(
                      avatar: Icon(Icons.payments_outlined, size: 16, color: _statusColor(status)),
                      label: Text(status.toUpperCase()),
                      backgroundColor: _statusColor(status).withValues(alpha: 0.12),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _detail('Chief complaint', visit['chief_complaint']),
                _detail('Findings', visit['findings']),
                _detail('Clinical notes', visit['clinical_notes']),
                _detail('Final diagnosis', visit['final_diagnosis']),
                if ((xray['requested'] ?? '') == 'Yes' || xray.isNotEmpty)
                  _detail(
                    'X-ray',
                    [
                      if ((xray['requested'] ?? '') == 'Yes') 'Requested',
                      if (xray['notes'] != null && '${xray['notes']}'.isNotEmpty)
                        'Notes: ${xray['notes']}',
                      if (xray['imageLink'] != null && '${xray['imageLink']}'.isNotEmpty)
                        'Link: ${xray['imageLink']}',
                    ].join('\n'),
                    trailing: (xray['imageLink'] != null && '${xray['imageLink']}'.isNotEmpty)
                        ? IconButton(
                            tooltip: 'Copy X-ray link',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: '${xray['imageLink']}'),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('X-ray link copied')),
                              );
                            },
                          )
                        : null,
                  ),
                const SizedBox(height: 12),
                const Text('Treatment plan', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (items.isEmpty)
                  const Text('No treatment items recorded.')
                else
                  ...items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item['name'] ?? 'Treatment'} × ${item['quantity'] ?? 1}',
                            ),
                          ),
                          Text(_money(_toDouble(item['cost']) * (int.tryParse('${item['quantity'] ?? 1}') ?? 1))),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 24),
                _totalRow('Subtotal', _toDouble(visit['subtotal'])),
                _totalRow('Discount', -_toDouble(visit['discount'])),
                _totalRow('Total', total, bold: true),
                _totalRow('Paid', paid),
                _totalRow('Balance', balance, bold: true, color: balance > 0 ? Colors.red : Colors.green),
                if (visit['payment_method'] != null &&
                    '${visit['payment_method']}'.isNotEmpty)
                  _detail('Payment method', visit['payment_method']),
                if (visit['payment_notes'] != null &&
                    '${visit['payment_notes']}'.isNotEmpty)
                  _detail('Payment notes', visit['payment_notes']),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (balance > 0)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kVisitListTeal),
              onPressed: () {
                Navigator.pop(context);
                _recordPayment(visit);
              },
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Record payment'),
            ),
        ],
      ),
    );
  }

  Widget _detail(String label, dynamic value, {Widget? trailing}) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          Text(
            _money(value),
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _recordPayment(Map<String, dynamic> visit) async {
    final total = _toDouble(visit['total']);
    final paid = _toDouble(visit['amount_paid']);
    final balance = (total - paid).clamp(0, double.infinity).toDouble();
    final amountController = TextEditingController(text: balance.toStringAsFixed(0));
    final notesController = TextEditingController(text: '${visit['payment_notes'] ?? ''}');
    final methods = ['Cash', 'Card', 'UPI', 'Bank transfer', 'Other'];
    var method = methods.contains(visit['payment_method'])
        ? visit['payment_method'].toString()
        : 'Cash';
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Record payment · ${visit['patient_name'] ?? ''}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance due: ${_money(balance)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: balance > 0 ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount received now',
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    border: OutlineInputBorder(),
                  ),
                  items: methods
                      .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => method = value ?? 'Cash'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kVisitListTeal),
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim()) ?? 0;
                if (amount <= 0) {
                  setDialogState(() => error = 'Enter an amount greater than zero');
                  return;
                }
                if (amount - balance > 0.009) {
                  setDialogState(() => error = 'Amount exceeds the balance due');
                  return;
                }
                final newPaid = paid + amount;
                final newStatus = newPaid + 0.009 >= total
                    ? 'paid'
                    : newPaid > 0
                        ? 'partial'
                        : 'unpaid';
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await Supabase.instance.client.from('visits').update({
                    'amount_paid': newPaid,
                    'payment_status': newStatus,
                    'payment_method': method,
                    'payment_notes': notesController.text.trim(),
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  }).eq('id', visit['id']);
                  if (!mounted) return;
                  navigator.pop();
                  await _loadVisits();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Payment recorded')),
                  );
                } catch (e) {
                  setDialogState(() => error = e.toString());
                }
              },
              child: const Text('Save payment'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    notesController.dispose();
  }

  Widget _statCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visits & Payments'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadVisits),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statCard('Visits', '${_visits.length}', kVisitListNavy, Icons.event_note_outlined),
                const SizedBox(width: 10),
                _statCard('Collected', _money(_totalCollected), Colors.green, Icons.savings_outlined),
                const SizedBox(width: 10),
                _statCard('Outstanding', _money(_totalOutstanding), Colors.red, Icons.request_quote_outlined),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search name, phone or diagnosis',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Payment status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All')),
                      DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                      DropdownMenuItem(value: 'partial', child: Text('Partial')),
                      DropdownMenuItem(value: 'paid', child: Text('Paid')),
                    ],
                    onChanged: (value) => setState(() => _statusFilter = value ?? 'All'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 42, color: Colors.red),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _loadVisits, child: const Text('Retry')),
                      ],
                    ),
                  ),
                ),
              )
            else if (filtered.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No visits match your filters.'),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final visit = filtered[index];
                    final status = (visit['payment_status'] ?? 'unpaid').toString();
                    final total = _toDouble(visit['total']);
                    final paid = _toDouble(visit['amount_paid']);
                    final balance = (total - paid).clamp(0, double.infinity).toDouble();
                    final items = _treatmentItems(visit);
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        onTap: () => _openVisit(visit),
                        leading: CircleAvatar(
                          backgroundColor: kVisitListTeal.withValues(alpha: 0.12),
                          child: const Icon(Icons.receipt_long_outlined, color: kVisitListTeal),
                        ),
                        title: Text(
                          '${visit['patient_name'] ?? 'Patient'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          [
                            '${visit['patient_phone'] ?? ''}',
                            _formatDate(visit['visit_date']),
                            if (items.isNotEmpty)
                              items.map((item) => item['name'] ?? '').where((name) => '$name'.isNotEmpty).join(', '),
                          ].where((part) => part.isNotEmpty).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: SizedBox(
                          width: 190,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _money(total),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    balance > 0 ? 'Due ${_money(balance)}' : 'Paid in full',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: balance > 0 ? Colors.red : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _statusColor(status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
