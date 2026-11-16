import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'consultation_call_screen.dart';

const Color kAppointmentTeal = Color(0xFF0D9488);
const Color kAppointmentNavy = Color(0xFF1E3A5F);

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  List<Map<String, dynamic>> _appointments = [];
  bool _loading = false;
  String? _error;
  String _searchQuery = '';
  String _typeFilter = 'All';
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('appointments')
          .select()
          .order('scheduled_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _appointments = List<Map<String, dynamic>>.from(rows);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _searchQuery.toLowerCase();
    return _appointments.where((appointment) {
      final type = (appointment['appointment_type'] ?? 'clinic').toString();
      final status = (appointment['status'] ?? 'pending').toString();
      final name = (appointment['patient_name'] ?? '').toString().toLowerCase();
      final phone = (appointment['patient_phone'] ?? '').toString().toLowerCase();
      final reason = (appointment['reason'] ?? '').toString().toLowerCase();

      if (_typeFilter != 'All' && type != _typeFilter) return false;
      if (_statusFilter != 'All' && status != _statusFilter) return false;
      if (query.isNotEmpty && !name.contains(query) && !phone.contains(query) && !reason.contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _updateStatus(Map<String, dynamic> appointment, String status) async {
    try {
      await Supabase.instance.client.from('appointments').update({
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', appointment['id']);
      await _loadAppointments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Appointment marked ${_capitalize(status)}'), backgroundColor: Colors.green),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update appointment: $error'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _joinConsultation(Map<String, dynamic> appointment) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConsultationCallScreen(
          appointmentId: appointment['id'].toString(),
          role: ConsultationRole.clinic,
          title: 'Online consultation',
          subtitle:
              '${appointment['patient_name'] ?? 'Patient'} - ${_formatScheduled(appointment['scheduled_at'])}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAppointments),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search patient, phone or reason...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _typeFilter,
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All types')),
                            DropdownMenuItem(value: 'online', child: Text('Online consultation')),
                            DropdownMenuItem(value: 'clinic', child: Text('Clinic visit')),
                          ],
                          onChanged: (value) => setState(() => _typeFilter = value ?? 'All'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All statuses')),
                            DropdownMenuItem(value: 'pending', child: Text('Pending')),
                            DropdownMenuItem(value: 'confirmed', child: Text('Confirmed')),
                            DropdownMenuItem(value: 'completed', child: Text('Completed')),
                            DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                          ],
                          onChanged: (value) => setState(() => _statusFilter = value ?? 'All'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      _loading ? 'Loading appointments...' : 'No appointments found',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadAppointments,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                      itemCount: _filtered.length,
                      itemBuilder: (_, index) {
                        final appointment = _filtered[index];
                        return _ClinicAppointmentCard(
                          appointment: appointment,
                          onJoin: () => _joinConsultation(appointment),
                          onStatusChanged: (status) => _updateStatus(appointment, status),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ClinicAppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final VoidCallback onJoin;
  final ValueChanged<String> onStatusChanged;

  const _ClinicAppointmentCard({
    required this.appointment,
    required this.onJoin,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final type = (appointment['appointment_type'] ?? 'clinic').toString();
    final status = (appointment['status'] ?? 'pending').toString();
    final isOnline = type == 'online';
    final patientName = (appointment['patient_name'] ?? 'Patient').toString();
    final phone = (appointment['patient_phone'] ?? '').toString();
    final clinic = (appointment['clinic'] ?? 'Dentehr Clinic').toString();
    final reason = (appointment['reason'] ?? '').toString();
    final doctor = (appointment['doctor_name'] ?? '').toString();
    final canJoin = isOnline && status != 'cancelled' && status != 'completed';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isOnline ? Colors.blue.shade50 : Colors.teal.shade50,
                  child: Icon(
                    isOnline ? Icons.video_call_outlined : Icons.local_hospital_outlined,
                    color: isOnline ? Colors.blue.shade700 : Colors.teal.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (phone.isNotEmpty)
                        Text(phone, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(isOnline ? Icons.videocam_outlined : Icons.calendar_month_outlined,
                    size: 15, color: kAppointmentNavy),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _formatScheduled(appointment['scheduled_at']),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kAppointmentNavy),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.blue.shade50 : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isOnline ? 'Online' : 'In-clinic',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isOnline ? Colors.blue.shade700 : Colors.teal.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.local_hospital_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(clinic, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ),
                if (doctor.isNotEmpty)
                  Text('Dr. $doctor', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  reason,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (canJoin)
                  FilledButton.icon(
                    onPressed: onJoin,
                    icon: const Icon(Icons.video_call, size: 18),
                    label: const Text('Join consultation'),
                    style: FilledButton.styleFrom(backgroundColor: kAppointmentTeal),
                  ),
                if (status == 'pending')
                  OutlinedButton(
                    onPressed: () => onStatusChanged('confirmed'),
                    child: const Text('Confirm'),
                  ),
                if (status == 'confirmed')
                  OutlinedButton(
                    onPressed: () => onStatusChanged('completed'),
                    child: const Text('Mark completed'),
                  ),
                if (status != 'cancelled' && status != 'completed')
                  TextButton(
                    onPressed: () => onStatusChanged('cancelled'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        _capitalize(status),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

String _formatScheduled(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'Date to be confirmed';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${months[date.month - 1]} ${date.day}, ${date.year} at $hour:$minute $period';
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

Color _statusColor(String status) {
  switch (status) {
    case 'confirmed':
      return Colors.blue;
    case 'completed':
      return Colors.green;
    case 'cancelled':
      return Colors.red;
    default:
      return Colors.orange;
  }
}
