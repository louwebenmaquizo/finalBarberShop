import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_session_service.dart';
import '../../services/booking_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/notifications_modal.dart';
import '../onboarding.dart';

class BarberHomeScreen extends StatefulWidget {
  final Map<String, dynamic>? barberData;

  const BarberHomeScreen({super.key, this.barberData});

  @override
  State<BarberHomeScreen> createState() => _BarberHomeScreenState();
}

class _BarberHomeScreenState extends State<BarberHomeScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _appointments = [];
  String _selectedFilter = 'today'; // 'today', 'upcoming', 'completed', 'all'
  String? _staffId;
  String _barberName = 'Master Barber';
  String? _profilePhoto;

  @override
  void initState() {
    super.initState();
    _initBarberInfo();
    _loadAppointments();
  }

  void _initBarberInfo() {
    final data = widget.barberData;
    if (data != null) {
      _staffId = data['staff_id'];
      _barberName = data['name'] ?? data['username'] ?? 'Barber';
      _profilePhoto = data['profile_photo'];
    }
  }

  Future<void> _loadAppointments() async {
    setState(() => _isLoading = true);
    try {
      final rows = await BookingService.getAllBookings();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final filtered = rows.where((appointment) {
        if (_staffId != null &&
            _staffId!.isNotEmpty &&
            appointment['staff_id']?.toString() != _staffId) {
          return false;
        }

        final start =
            DateTime.tryParse(appointment['start_time']?.toString() ?? '')
                ?.toLocal();
        if (_selectedFilter == 'today') {
          return start != null &&
              start.year == today.year &&
              start.month == today.month &&
              start.day == today.day;
        }
        if (_selectedFilter == 'upcoming') {
          return start != null && !start.isBefore(now);
        }
        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _appointments = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateAppointmentStatus(
      String appointmentId, String newStatus) async {
    try {
      final response = await BookingService.updateBooking(
        appointmentId,
        {'status': newStatus},
      );

      if (response['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'completed'
                  ? 'Great cut! Appointment marked as completed.'
                  : newStatus == 'in_progress'
                      ? 'Haircut started! Customer is in the chair.'
                      : 'Status updated to $newStatus',
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: newStatus == 'completed'
                ? Colors.green
                : const Color(0xFF1E88E5),
          ),
        );
        _loadAppointments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error updating status: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddNoteDialog(Map<String, dynamic> appointment) {
    final TextEditingController noteController = TextEditingController(
      text: appointment['notes'] ?? '',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit_note, color: Color(0xFF1E88E5)),
            const SizedBox(width: 8),
            Text('Haircut Notes',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer: ${appointment['customer_name'] ?? 'Guest'} • ${appointment['service_name'] ?? 'Service'}',
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    'e.g. Skin fade #1.5 on sides, scissor texture on top, matte clay styling...',
                hintStyle:
                    GoogleFonts.manrope(fontSize: 13, color: Colors.grey[400]),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              style: GoogleFonts.manrope(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await BookingService.updateBooking(
                  appointment['appointment_id'].toString(),
                  {'notes': noteController.text.trim()},
                );
                _loadAppointments();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Haircut note saved!',
                            style: GoogleFonts.manrope()),
                        backgroundColor: Colors.green),
                  );
                }
              } catch (_) {}
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5BBCFF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Save Note',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Log Out',
            style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to log out of the Barber Portal?',
            style: GoogleFonts.manrope()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthSessionService.clearSession();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const OnboardingScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Log Out',
                style: GoogleFonts.manrope(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBarberHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          // Barber Avatar
          _buildAvatar(_profilePhoto, _barberName, size: 54),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _barberName,
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x1A5BBCFF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Barber',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E88E5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "Today's Customer Queue",
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // Actions
          ValueListenableBuilder<int>(
            valueListenable: NotificationService.unreadCountNotifier,
            builder: (context, unreadCount, _) {
              return IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_outlined,
                        color: Colors.black87),
                    if (unreadCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1E88E5),
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 14,
                            minHeight: 14,
                          ),
                          child: Center(
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () => showNotificationsModal(
                  context,
                  isAdmin: false,
                  staffId: _staffId,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: _handleLogout,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final totalToday = _appointments.length;
    final inProgress =
        _appointments.where((a) => a['status'] == 'in_progress').length;
    final completed =
        _appointments.where((a) => a['status'] == 'completed').length;
    final waiting = _appointments.where((a) => a['status'] == 'booked').length;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
              child: _buildStatCard(
                  'Total Cuts', '$totalToday', Colors.blue, Icons.content_cut)),
          const SizedBox(width: 8),
          Expanded(
              child: _buildStatCard(
                  'Waiting', '$waiting', Colors.orange, Icons.access_time)),
          const SizedBox(width: 8),
          Expanded(
              child: _buildStatCard('In Chair', '$inProgress', Colors.purple,
                  Icons.airline_seat_recline_extra)),
          const SizedBox(width: 8),
          Expanded(
              child: _buildStatCard('Finished', '$completed', Colors.green,
                  Icons.check_circle_outline)),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.manrope(
                fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            label,
            style: GoogleFonts.manrope(
                fontSize: 10,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildChip('Today\'s Cuts', 'today'),
          const SizedBox(width: 8),
          _buildChip('All Upcoming', 'upcoming'),
          const SizedBox(width: 8),
          _buildChip('All Appointments', 'all'),
        ],
      ),
    );
  }

  Widget _buildChip(String label, String filter) {
    final isSelected = _selectedFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = filter);
          _loadAppointments();
        }
      },
      selectedColor: const Color(0xFF5BBCFF),
      labelStyle: GoogleFonts.manrope(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        fontSize: 13,
      ),
      backgroundColor: Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final customerName = appointment['customer_name'] ?? 'Guest Customer';
    final customerPhone = appointment['customer_phone'] ?? '';
    final customerPhoto = appointment['customer_photo'];
    final serviceName = appointment['service_name'] ?? 'Haircut';
    final timeStr = appointment['time'] ?? 'Scheduled';
    final dateStr = appointment['date'] ?? '';
    final status = appointment['status'] ?? 'booked';
    final notes = appointment['notes'] ?? '';
    final price = appointment['service_price'] ?? '0.00';
    final appointmentId = appointment['appointment_id'] ?? '';

    Color statusColor = Colors.blue;
    String statusLabel = 'Confirmed';
    if (status == 'pending') {
      statusColor = Colors.orange[800]!;
      statusLabel = 'Pending Approval';
    } else if (status == 'in_progress') {
      statusColor = Colors.purple;
      statusLabel = 'In Progress';
    } else if (status == 'completed') {
      statusColor = Colors.green;
      statusLabel = 'Completed';
    } else if (status == 'canceled') {
      statusColor = Colors.red;
      statusLabel = 'Canceled';
    } else if (status == 'declined') {
      statusColor = Colors.red[700]!;
      statusLabel = 'Declined';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'in_progress'
              ? const Color(0xFF5BBCFF)
              : status == 'pending'
                  ? Colors.orange[300]!
                  : Colors.grey[200]!,
          width: status == 'in_progress' || status == 'pending' ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Customer Info & Status
            Row(
              children: [
                _buildAvatar(customerPhoto, customerName, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (customerPhone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.phone,
                                size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              customerPhone,
                              style: GoogleFonts.manrope(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Service & Time Details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.content_cut,
                        size: 16, color: Color(0xFF1E88E5)),
                    const SizedBox(width: 6),
                    Text(
                      serviceName,
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Text(
                  '\$$price',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: const Color(0xFF0F8751)),
                ),
              ],
            ),
            const SizedBox(height: 6),

            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  '$timeStr  •  $dateStr',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: Colors.grey[700]),
                ),
              ],
            ),

            // Customer Haircut Notes
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.note_alt, size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        notes,
                        style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: Colors.brown[800],
                            height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Barber Action Buttons
            Row(
              children: [
                // Add / Edit Haircut Note
                OutlinedButton.icon(
                  onPressed: () => _showAddNoteDialog(appointment),
                  icon: const Icon(Icons.note_add_outlined, size: 16),
                  label: Text('Note', style: GoogleFonts.manrope(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const Spacer(),

                // PENDING APPROVAL: Accept and Decline Buttons
                if (status == 'pending') ...[
                  OutlinedButton.icon(
                    onPressed: () => _confirmDeclineAppointment(appointment),
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: Text('Decline',
                        style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _updateAppointmentStatus(appointmentId, 'booked'),
                    icon:
                        const Icon(Icons.check, size: 16, color: Colors.white),
                    label: Text('Accept',
                        style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],

                // CONFIRMED / BOOKED: Start Cut Button
                if (status == 'booked' || status == 'confirmed') ...[
                  ElevatedButton.icon(
                    onPressed: () =>
                        _updateAppointmentStatus(appointmentId, 'in_progress'),
                    icon: const Icon(Icons.play_arrow,
                        size: 16, color: Colors.white),
                    label: Text('Start Cut',
                        style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5BBCFF),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],

                // IN PROGRESS: Complete Cut Button
                if (status == 'in_progress') ...[
                  ElevatedButton.icon(
                    onPressed: () =>
                        _updateAppointmentStatus(appointmentId, 'completed'),
                    icon:
                        const Icon(Icons.check, size: 16, color: Colors.white),
                    label: Text('Complete Cut',
                        style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeclineAppointment(Map<String, dynamic> appointment) {
    final appointmentId = appointment['appointment_id'] ?? '';
    final customerName = appointment['customer_name'] ?? 'Customer';
    final serviceName = appointment['service_name'] ?? 'Haircut';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text('Decline Booking',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to decline the booking request from $customerName for $serviceName?',
          style: GoogleFonts.manrope(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateAppointmentStatus(appointmentId, 'declined');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Decline Request',
                style: GoogleFonts.manrope(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String? photo, String name, {double size = 48}) {
    if (photo != null && photo.trim().isNotEmpty) {
      String clean = photo.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF5BBCFF), width: 1.5)),
          child: ClipOval(
            child: Image.network(
              clean,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallbackAvatar(name, size),
            ),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(
            base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF5BBCFF), width: 1.5)),
          child: ClipOval(child: Image.memory(bytes, fit: BoxFit.cover)),
        );
      } catch (_) {}
    }
    return _buildFallbackAvatar(name, size);
  }

  Widget _buildFallbackAvatar(String name, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x1A5BBCFF),
        border: Border.all(color: const Color(0xFF5BBCFF), width: 1.5),
      ),
      child: Center(
        child: Text(
          (name.isNotEmpty ? name[0] : 'B').toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: size * 0.42,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E88E5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadAppointments,
            child: Column(
              children: [
                _buildBarberHeader(),
                Expanded(
                  child: ListView(
                    children: [
                      _buildStatsRow(),
                      _buildFilterChips(),
                      const SizedBox(height: 12),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.all(40.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_appointments.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(40),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.content_cut,
                                    size: 48, color: Color(0xFF1E88E5)),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Cuts in Queue',
                                style: GoogleFonts.manrope(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedFilter == 'today'
                                    ? 'No customers scheduled for cuts today.'
                                    : 'No appointments found for this filter.',
                                style: GoogleFonts.manrope(
                                    color: Colors.grey[600], fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        ..._appointments.map(
                            (appointment) => _buildAppointmentCard(appointment)),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
