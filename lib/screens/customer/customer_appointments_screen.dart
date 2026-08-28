import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../services/booking_service.dart';
import '../admin/reschedule_screen.dart';

class CustomerAppointmentsScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  
  const CustomerAppointmentsScreen({super.key, this.userData});

  @override
  State<CustomerAppointmentsScreen> createState() => _CustomerAppointmentsScreenState();
}

class _CustomerAppointmentsScreenState extends State<CustomerAppointmentsScreen> {
  List<dynamic> _appointments = [];
  List<dynamic> _filteredAppointments = [];
  bool _isLoading = true;
  String? _customerId;
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'upcoming', 'completed', 'canceled'
  final TextEditingController _searchController = TextEditingController();
  Map<String, bool> _hasFeedbackMap = {}; // appointment_id -> hasFeedback

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _filterAppointments();
      });
    });
    _initializeData();
  }

  Future<void> _initializeData() async {
    // Load customer_id first, then load appointments
    await _loadCustomerId();
    _loadAppointments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerId() async {
    if (widget.userData == null) {
      print('⚠️ userData is null');
      return;
    }
    
    // Check if customer_id is already present in userData
    final directId = widget.userData!['customer_id'];
    if (directId != null && directId.toString().isNotEmpty) {
      if (mounted) {
        setState(() {
          _customerId = directId.toString();
        });
      }
      return;
    }
    
    try {
      final email = widget.userData!['email'] ?? '';
      final phone = widget.userData!['phone'] ?? '';
      
      print('🔍 Looking for customer with email: $email, phone: $phone');
      
      if (email.isEmpty && phone.isEmpty) {
        print('⚠️ Both email and phone are empty');
        return;
      }
      
      final customers = await ApiService.getCustomers();
      print('📋 Found ${customers.length} customers in database');
      
      // Find customer by email or phone
      Map<String, dynamic>? foundCustomer;
      for (var c in customers) {
        final cEmail = (c['email'] ?? '').toString().toLowerCase();
        final cPhone = (c['phone'] ?? '').toString();
        
        if ((email.isNotEmpty && cEmail == email.toLowerCase()) ||
            (phone.isNotEmpty && cPhone == phone)) {
          foundCustomer = c as Map<String, dynamic>?;
          print('✅ Found matching customer: ${foundCustomer!['customer_id']}');
          break;
        }
      }
      
      if (foundCustomer != null && foundCustomer['customer_id'] != null) {
        if (mounted) {
          setState(() {
            _customerId = foundCustomer!['customer_id'];
          });
        }
        print('✅ Customer ID set to: $_customerId');
      } else {
        print('❌ No matching customer found');
      }
    } catch (e) {
      print('❌ Error loading customer ID: $e');
    }
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load customer_id first if not already loaded
      if (_customerId == null && widget.userData != null) {
        await _loadCustomerId();
      }
      
      // Ensure we have customer_id before loading appointments
      if (_customerId == null || _customerId!.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to identify customer. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      print('Loading appointments for customer_id: $_customerId');
      
      // Get all appointments for this customer (not just upcoming, includes canceled)
      final appointments = await ApiService.getAppointments(customerId: _customerId);
      
      print('Loaded ${appointments.length} appointments for customer');
      
      // Check feedback status for each appointment
      final feedbackMap = <String, bool>{};
      for (var appointment in appointments) {
        final appointmentId = appointment['appointment_id'] ?? '';
        if (appointmentId.isNotEmpty && _customerId != null) {
          final hasFeedback = await ApiService.hasFeedback(appointmentId, _customerId!);
          feedbackMap[appointmentId] = hasFeedback;
        }
      }
      
      setState(() {
        _appointments = appointments;
        _hasFeedbackMap = feedbackMap;
        _isLoading = false;
      });
      
      _filterAppointments();
    } catch (e) {
      print('Error loading appointments: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading appointments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterAppointments() {
    var filtered = List<dynamic>.from(_appointments);
    
    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((apt) {
        final serviceName = (apt['service_name'] ?? '').toString().toLowerCase();
        final staffName = (apt['staff_name'] ?? '').toString().toLowerCase();
        final date = (apt['date'] ?? '').toString().toLowerCase();
        return serviceName.contains(query) || 
               staffName.contains(query) || 
               date.contains(query);
      }).toList();
    }
    
    // Filter by status
    if (_statusFilter != 'all') {
      filtered = filtered.where((apt) {
        final apptStatus = _getAppointmentStatus(apt);
        return apptStatus == _statusFilter;
      }).toList();
    }
    
    setState(() {
      _filteredAppointments = filtered;
    });
  }

  void _setStatusFilter(String status) {
    setState(() {
      _statusFilter = status;
      _filterAppointments();
    });
  }

  Future<void> _cancelAppointment(Map<String, dynamic> appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Cancel Appointment',
          style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to cancel this appointment?',
          style: GoogleFonts.manrope(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'No',
              style: GoogleFonts.manrope(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(
              'Yes, Cancel',
              style: GoogleFonts.manrope(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final appointmentId = appointment['appointment_id'];
      final result = await BookingService.cancelBooking(appointmentId);
      
      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Appointment canceled successfully',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.green,
            ),
          );
          _loadAppointments();
        }
      } else {
        throw Exception('Failed to cancel appointment');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error canceling appointment: ${e.toString()}',
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRatingDialog(Map<String, dynamic> appointment) {
    int selectedRating = 0;
    final TextEditingController commentsController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Rate Your Service',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(
                  'How would you rate your experience?',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),
                // Star Rating
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starNumber = index + 1;
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            selectedRating = starNumber;
                          });
                        },
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: index == 0 ? 0 : 4,
                            right: index == 4 ? 0 : 4,
                          ),
                          child: Icon(
                            starNumber <= selectedRating
                                ? Icons.star
                                : Icons.star_border,
                            color: starNumber <= selectedRating
                                ? Colors.amber
                                : Colors.grey[400],
                            size: 32,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 24),
                // Comments Field
                Text(
                  'Comments (Optional)',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: commentsController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Share your experience...',
                    hintStyle: GoogleFonts.manrope(
                      color: Colors.grey[400],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xB25BBCFF),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  style: GoogleFonts.manrope(),
                ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () {
                      Navigator.pop(context);
                      commentsController.dispose();
                    },
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: isSubmitting || selectedRating == 0
                  ? null
                  : () async {
                      setDialogState(() {
                        isSubmitting = true;
                      });

                      try {
                        final appointmentId = appointment['appointment_id'] ?? '';
                        final customerId = _customerId ?? '';

                        if (appointmentId.isEmpty || customerId.isEmpty) {
                          throw Exception('Missing appointment or customer ID');
                        }

                        final result = await ApiService.submitFeedback(
                          appointmentId: appointmentId,
                          customerId: customerId,
                          rating: selectedRating,
                          comments: commentsController.text.trim().isNotEmpty
                              ? commentsController.text.trim()
                              : null,
                        );

                        // Close dialog and dispose controller first
                        commentsController.dispose();
                        if (mounted) {
                          Navigator.pop(context);
                        }

                        // Wait a frame before showing messages and reloading
                        await Future.delayed(const Duration(milliseconds: 100));

                        if (mounted) {
                          if (result['success'] == true) {
                            // Update feedback map immediately to show green button
                            setState(() {
                              _hasFeedbackMap[appointmentId] = true;
                            });
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Thank you for your feedback!',
                                  style: GoogleFonts.manrope(),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                            // Reload appointments to refresh the UI
                            _loadAppointments();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  result['message'] ?? 'Failed to submit feedback',
                                  style: GoogleFonts.manrope(),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        // Close dialog and dispose controller first
                        commentsController.dispose();
                        if (mounted) {
                          Navigator.pop(context);
                        }

                        // Wait a frame before showing error
                        await Future.delayed(const Duration(milliseconds: 100));

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Error: ${e.toString()}',
                                style: GoogleFonts.manrope(),
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xB25BBCFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Submit',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _getAppointmentStatus(Map<String, dynamic> appointment) {
    final status = (appointment['status'] ?? '').toString().toLowerCase();
    
    if (status == 'canceled' || status == 'cancelled') {
      return 'canceled';
    } else if (status == 'declined') {
      return 'declined';
    } else if (status == 'pending') {
      return 'pending';
    } else if (status == 'completed') {
      return 'completed';
    }
    
    // Check if appointment date is strictly in the past (before today)
    final startTime = appointment['start_time'];
    if (startTime != null) {
      try {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        DateTime? appointmentDate;
        final startTimeStr = startTime.toString();
        
        if (startTimeStr.contains('T')) {
          appointmentDate = DateTime.tryParse(startTimeStr);
        } else {
          final parts = startTimeStr.split(' ');
          if (parts.isNotEmpty) {
            final dateParts = parts[0].split('-');
            if (dateParts.length == 3) {
              appointmentDate = DateTime(
                int.tryParse(dateParts[0]) ?? 0,
                int.tryParse(dateParts[1]) ?? 1,
                int.tryParse(dateParts[2]) ?? 1,
              );
            }
          }
        }
        
        if (appointmentDate != null) {
          final appointmentDay = DateTime(appointmentDate.year, appointmentDate.month, appointmentDate.day);
          // If the appointment day was before today, mark as completed
          if (appointmentDay.isBefore(today)) {
            return 'completed';
          }
        }
      } catch (e) {
        print('Error parsing appointment date: $e');
      }
    }
    
    // Today's appointments and future bookings are active / upcoming
    return 'upcoming';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Fixed Header Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search appointments...',
                      hintStyle: GoogleFonts.manrope(
                        color: Colors.grey[600],
                      ),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: GoogleFonts.manrope(),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Status Filter Buttons (Horizontal)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildStatusButton('All', 'all'),
                      const SizedBox(width: 8),
                      _buildStatusButton('Pending', 'pending'),
                      const SizedBox(width: 8),
                      _buildStatusButton('Upcoming', 'upcoming'),
                      const SizedBox(width: 8),
                      _buildStatusButton('Completed', 'completed'),
                      const SizedBox(width: 8),
                      _buildStatusButton('Canceled', 'canceled'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Scrollable Appointments List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredAppointments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No appointments found',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAppointments,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredAppointments.length,
                          itemBuilder: (context, index) {
                            return _buildAppointmentCard(_filteredAppointments[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusButton(String label, String status) {
    final isSelected = _statusFilter == status;
    return ElevatedButton(
      onPressed: () => _setStatusFilter(status),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xB25BBCFF) : Colors.white,
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        side: BorderSide(
          color: isSelected ? const Color(0xB25BBCFF) : Colors.grey[300]!,
          width: 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 0,
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final status = _getAppointmentStatus(appointment);
    final serviceName = appointment['service_name'] ?? 'Service';
    final date = appointment['date'] ?? '';
    final time = appointment['time'] ?? '';
    final staffName = appointment['staff_name'] ?? 'Barber';
    final price = appointment['price'] ?? appointment['service_price'] ?? '0.00';
    final serviceImage = appointment['service_image'] ?? appointment['image_url'];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service Image
          _buildAppointmentImage(
            serviceImage,
            width: 100,
            height: 120,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
          ),
          // Service Info and Actions
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Service Name
                  Text(
                    serviceName,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Date and Time
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        date,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        time,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Barber Name
                  Row(
                    children: [
                      Icon(Icons.person, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        staffName,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Price
                  Text(
                    '\$${price.toString()}',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F8751),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Status and Action Buttons
                  if (status == 'canceled')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[300]!),
                      ),
                      child: Text(
                        'Canceled',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red[700],
                        ),
                      ),
                    )
                  else if (status == 'declined')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[300]!),
                      ),
                      child: Text(
                        'Declined by Barber',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red[700],
                        ),
                      ),
                    )
                  else if (status == 'pending')
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange[300]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule, size: 14, color: Colors.orange),
                              const SizedBox(width: 4),
                              Text(
                                'Pending Approval',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _cancelAppointment(appointment),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (status == 'upcoming')
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RescheduleScreen(
                                    booking: appointment,
                                  ),
                                ),
                              ).then((success) {
                                if (success == true) {
                                  _loadAppointments();
                                }
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xB25BBCFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Reschedule',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _cancelAppointment(appointment),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (status == 'completed')
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[300]!),
                          ),
                          child: Text(
                            'Completed',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[700],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _hasFeedbackMap[appointment['appointment_id']] == true
                                ? null // Disable if feedback exists
                                : () => _showRatingDialog(appointment),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hasFeedbackMap[appointment['appointment_id']] == true
                                  ? Colors.green
                                  : Colors.amber,
                              disabledBackgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _hasFeedbackMap[appointment['appointment_id']] == true
                                      ? Icons.check_circle
                                      : Icons.star,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _hasFeedbackMap[appointment['appointment_id']] == true
                                      ? 'Rated'
                                      : 'Rate',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentImage(String? photo, {double width = 100, double height = 120, BorderRadius? borderRadius}) {
    final radius = borderRadius ?? BorderRadius.circular(8);
    if (photo != null && photo.trim().isNotEmpty) {
      String clean = photo.trim();
      if (!clean.startsWith('http://') && !clean.startsWith('https://') && !clean.startsWith('data:image')) {
        if (clean.startsWith('/')) {
          clean = 'http://localhost$clean';
        } else if (clean.startsWith('uploads/')) {
          clean = 'http://localhost/barber_api/$clean';
        }
      }

      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return ClipRRect(
          borderRadius: radius,
          child: Image.network(
            clean,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackImage(width, height, radius),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return ClipRRect(
          borderRadius: radius,
          child: Image.memory(
            bytes,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackImage(width, height, radius),
          ),
        );
      } catch (_) {}
    }
    return _buildFallbackImage(width, height, radius);
  }

  Widget _buildFallbackImage(double width, double height, BorderRadius radius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xB25BBCFF),
        borderRadius: radius,
      ),
      child: const Icon(Icons.content_cut, color: Colors.white, size: 32),
    );
  }
}

