import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../services/booking_service.dart';
import '../../services/catalog_service.dart';
import '../../services/employee_service.dart';

class CustomerBookingScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final Map<String, dynamic>? preSelectedService;

  const CustomerBookingScreen({
    super.key,
    this.userData,
    this.preSelectedService,
  });

  @override
  State<CustomerBookingScreen> createState() => _CustomerBookingScreenState();
}

class _CustomerBookingScreenState extends State<CustomerBookingScreen> {
  List<dynamic> _services = [];
  List<dynamic> _staff = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _customerId;

  // Selected values
  String? _selectedServiceId;
  String? _selectedStaffId;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // Booked intervals & conflict state for selected barber + date
  List<Map<String, dynamic>> _bookedIntervals = [];
  bool _isLoadingIntervals = false;
  Map<String, dynamic>? _conflictingInterval;

  // Standard business hour slots (8:00 AM to 6:00 PM)
  static final List<TimeOfDay> _standardTimeSlots = [
    const TimeOfDay(hour: 8, minute: 0),
    const TimeOfDay(hour: 8, minute: 30),
    const TimeOfDay(hour: 9, minute: 0),
    const TimeOfDay(hour: 9, minute: 30),
    const TimeOfDay(hour: 10, minute: 0),
    const TimeOfDay(hour: 10, minute: 30),
    const TimeOfDay(hour: 11, minute: 0),
    const TimeOfDay(hour: 11, minute: 30),
    const TimeOfDay(hour: 12, minute: 0),
    const TimeOfDay(hour: 12, minute: 30),
    const TimeOfDay(hour: 13, minute: 0),
    const TimeOfDay(hour: 13, minute: 30),
    const TimeOfDay(hour: 14, minute: 0),
    const TimeOfDay(hour: 14, minute: 30),
    const TimeOfDay(hour: 15, minute: 0),
    const TimeOfDay(hour: 15, minute: 30),
    const TimeOfDay(hour: 16, minute: 0),
    const TimeOfDay(hour: 16, minute: 30),
    const TimeOfDay(hour: 17, minute: 0),
    const TimeOfDay(hour: 17, minute: 30),
    const TimeOfDay(hour: 18, minute: 0),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.preSelectedService != null) {
      _selectedServiceId = widget.preSelectedService!['service_id'];
    }
    _loadBookingData();
  }

  Future<void> _loadBookingData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadCustomerId();

      final results = await Future.wait([
        CatalogService.getAllServices(),
        EmployeeService.getAllEmployees(),
      ]);

      final services = results[0] as List<dynamic>;
      final employees = results[1] as List<dynamic>;

      final activeServices = services.where((s) {
        final isActive = s['is_active'];
        if (isActive is bool) return isActive;
        if (isActive is int) return isActive == 1;
        if (isActive is String) {
          return isActive == '1' || isActive.toLowerCase() == 'true';
        }
        return true;
      }).toList();

      final barbers = employees.where((e) {
        final isActive = e['is_active'];
        bool active = false;
        if (isActive is bool) {
          active = isActive;
        } else if (isActive is int) {
          active = isActive == 1;
        } else if (isActive is String) {
          active = isActive == '1' || isActive.toLowerCase() == 'true';
        }

        final role = (e['role'] ?? '').toString().toLowerCase().trim();
        final isNonBarber =
            role == 'admin' || role == 'administrator' || role == 'cashier';
        return active && !isNonBarber;
      }).toList();

      setState(() {
        _services = activeServices;
        _staff = barbers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadCustomerId() async {
    if (widget.userData == null) return;

    final directId =
        widget.userData!['customer_id'] ?? widget.userData!['id'];
    if (directId != null && directId.toString().isNotEmpty) {
      if (mounted) {
        setState(() {
          _customerId = directId.toString();
        });
      }
      return;
    }

    try {
      final userId =
          (widget.userData!['user_id'] ?? widget.userData!['id'] ?? '').toString();
      if (userId.isNotEmpty) {
        final cust = await ApiService.getCustomerByUserId(userId);
        if (cust != null && cust['customer_id'] != null && mounted) {
          setState(() {
            _customerId = cust['customer_id'].toString();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadBookedIntervals() async {
    if (_selectedStaffId == null || _selectedDate == null) {
      setState(() {
        _bookedIntervals = [];
        _conflictingInterval = null;
      });
      return;
    }

    setState(() => _isLoadingIntervals = true);

    try {
      final intervals = await BookingService.getStaffBookedIntervals(
        staffId: _selectedStaffId!,
        date: _selectedDate!,
      );

      if (mounted) {
        setState(() {
          _bookedIntervals = intervals;
          _isLoadingIntervals = false;
          _recheckConflict();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingIntervals = false);
    }
  }

  int _getServiceDuration() {
    if (_selectedServiceId == null) return 30;
    for (var service in _services) {
      if (service['service_id'] == _selectedServiceId) {
        dynamic durationValue = service['duration_minutes'] ?? 30;
        if (durationValue is int) return durationValue;
        if (durationValue is double) return durationValue.toInt();
        if (durationValue is String) return int.tryParse(durationValue) ?? 30;
        if (durationValue is num) return durationValue.toInt();
      }
    }
    return 30;
  }

  void _recheckConflict() {
    if (_selectedDate == null || _selectedTime == null || _selectedStaffId == null) {
      _conflictingInterval = null;
      return;
    }

    final duration = _getServiceDuration();
    final startDt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
    final endDt = startDt.add(Duration(minutes: duration));

    _conflictingInterval = BookingService.findConflictingBooking(
      proposedStart: startDt,
      proposedEnd: endDt,
      existingIntervals: _bookedIntervals,
    );
  }

  bool _isSlotBooked(TimeOfDay time) {
    if (_selectedDate == null || _bookedIntervals.isEmpty) return false;
    final duration = _getServiceDuration();
    final startDt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      time.hour,
      time.minute,
    );
    final endDt = startDt.add(Duration(minutes: duration));

    final conflict = BookingService.findConflictingBooking(
      proposedStart: startDt,
      proposedEnd: endDt,
      existingIntervals: _bookedIntervals,
    );
    return conflict != null;
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = now.add(const Duration(days: 90));

    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate ?? firstDate,
        firstDate: firstDate,
        lastDate: lastDate,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF5BBCFF),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          _selectedDate = picked;
        });
        await _loadBookedIntervals();
      }
    } catch (_) {}
  }

  Future<void> _selectTime() async {
    try {
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: _selectedTime ?? TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF5BBCFF),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          _selectedTime = picked;
          _recheckConflict();
        });
      }
    } catch (_) {}
  }

  Future<void> _submitBooking() async {
    if (_selectedServiceId == null ||
        _selectedStaffId == null ||
        _selectedDate == null ||
        _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please fill in all fields',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _recheckConflict();
    if (_conflictingInterval != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot book: ${_getBarberName()} is already booked from ${_conflictingInterval!['start_formatted']} to ${_conflictingInterval!['end_formatted']}. Please choose another time.',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (_customerId == null || _customerId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to identify customer. Please try again.',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Booking',
          style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please confirm your appointment details:',
              style: GoogleFonts.manrope(),
            ),
            const SizedBox(height: 12),
            _buildConfirmationRow('Service', _getServiceName()),
            _buildConfirmationRow('Barber', _getBarberName()),
            _buildConfirmationRow('Date', _formatDate(_selectedDate!)),
            _buildConfirmationRow('Time', _selectedTime!.format(context)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.manrope(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5BBCFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Confirm',
              style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final durationMinutes = _getServiceDuration();

      final dateStr =
          '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00';
      final startTime = '$dateStr $timeStr';

      final startDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      final endDateTime = startDateTime.add(Duration(minutes: durationMinutes));
      final endTime =
          '${endDateTime.year}-${endDateTime.month.toString().padLeft(2, '0')}-${endDateTime.day.toString().padLeft(2, '0')} ${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}:00';

      final appointmentData = {
        'customer_id': _customerId,
        'staff_id': _selectedStaffId,
        'service_id': _selectedServiceId,
        'start_time': startTime,
        'end_time': endTime,
      };

      final result = await ApiService.createAppointment(appointmentData);

      if (result != null && result['appointment_id'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Appointment booked successfully!',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              backgroundColor: Colors.green[700],
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception('Failed to create appointment');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceAll('Exception:', '').trim(),
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildConfirmationRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.manrope(),
            ),
          ),
        ],
      ),
    );
  }

  String _getServiceName() {
    try {
      if (_selectedServiceId == null) return 'Unknown';
      for (var service in _services) {
        if (service['service_id'] == _selectedServiceId) {
          return service['name'] ?? 'Unknown';
        }
      }
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  String _getBarberName() {
    try {
      if (_selectedStaffId == null) return 'Unknown';
      for (var barber in _staff) {
        if (barber['staff_id'] == _selectedStaffId) {
          return barber['name'] ?? 'Unknown';
        }
      }
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  String _formatDate(DateTime date) {
    final months = [
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
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Book Appointment',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5BBCFF)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Service Selection
                  Text(
                    'Select Service',
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedServiceId,
                      dropdownColor: Colors.white,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
                      style: GoogleFonts.manrope(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        hintText: 'Choose a service',
                        hintStyle: GoogleFonts.manrope(
                          color: Colors.grey[600],
                        ),
                      ),
                      items: _services.isEmpty
                          ? [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  'No services available',
                                  style: GoogleFonts.manrope(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ]
                          : _services.map<DropdownMenuItem<String>>((service) {
                              final duration = service['duration_minutes'] ?? 30;
                              final price = service['price'] ?? 0;
                              return DropdownMenuItem<String>(
                                value: service['service_id'] as String?,
                                child: Text(
                                  '${service['name']} - ₱$price ($duration mins)',
                                  style: GoogleFonts.manrope(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedServiceId = value;
                          _recheckConflict();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Staff Selection
                  Text(
                    'Select Barber',
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedStaffId,
                      dropdownColor: Colors.white,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
                      style: GoogleFonts.manrope(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        hintText: 'Choose a barber',
                        hintStyle: GoogleFonts.manrope(
                          color: Colors.grey[600],
                        ),
                      ),
                      items: _staff.isEmpty
                          ? [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  'No barbers available',
                                  style: GoogleFonts.manrope(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ]
                          : _staff.map<DropdownMenuItem<String>>((staff) {
                              return DropdownMenuItem<String>(
                                value: staff['staff_id'] as String?,
                                child: Row(
                                  children: [
                                    _buildSmallAvatar(staff['profile_photo'],
                                        staff['name'] ?? 'B'),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${staff['name'] ?? 'Barber'} (${staff['role'] ?? 'Stylist'})',
                                      style: GoogleFonts.manrope(
                                        color: Colors.black87,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedStaffId = value;
                        });
                        _loadBookedIntervals();
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Date Selection
                  Text(
                    'Select Date',
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _selectDate,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedDate == null
                                ? 'Choose a date'
                                : _formatDate(_selectedDate!),
                            style: GoogleFonts.manrope(
                              color: _selectedDate == null
                                  ? Colors.grey[600]
                                  : Colors.black,
                              fontWeight: _selectedDate == null
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                          const Icon(Icons.calendar_today, color: Color(0xFF5BBCFF)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Time Slots Section (Quick visual slots + availability)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Time Slot',
                        style: GoogleFonts.manrope(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      if (_selectedStaffId != null && _selectedDate != null)
                        TextButton.icon(
                          onPressed: _selectTime,
                          icon: const Icon(Icons.edit_calendar, size: 16, color: Color(0xFF1E88E5)),
                          label: Text(
                            'Custom Time',
                            style: GoogleFonts.manrope(
                              fontSize: 12.5,
                              color: const Color(0xFF1E88E5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_selectedStaffId == null || _selectedDate == null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.grey, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Please select a barber and date first to view real-time availability.',
                              style: GoogleFonts.manrope(fontSize: 13, color: Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_isLoadingIntervals)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF5BBCFF)),
                      ),
                    )
                  else
                    _buildTimeSlotsGrid(),

                  // Conflict Alert Banner
                  if (_conflictingInterval != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red[800], size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Time Slot Unavailable',
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.red[900],
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${_getBarberName()} already has a booking from ${_conflictingInterval!['start_formatted']} to ${_conflictingInterval!['end_formatted']}. Please choose an open slot.',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12.5,
                                    color: Colors.red[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_isSubmitting || _conflictingInterval != null)
                          ? null
                          : _submitBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5BBCFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        disabledBackgroundColor: Colors.grey[300],
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              _conflictingInterval != null
                                  ? 'Slot Unavailable (Conflict)'
                                  : 'Book Appointment',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTimeSlotsGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _standardTimeSlots.map((slot) {
        final isBooked = _isSlotBooked(slot);
        final isSelected = _selectedTime != null &&
            _selectedTime!.hour == slot.hour &&
            _selectedTime!.minute == slot.minute;

        Color chipBg;
        Color textColor;
        BorderSide borderSide;

        if (isSelected) {
          chipBg = const Color(0xFF5BBCFF);
          textColor = Colors.white;
          borderSide = const BorderSide(color: Color(0xFF5BBCFF), width: 1.5);
        } else if (isBooked) {
          chipBg = Colors.red[50]!;
          textColor = Colors.red[400]!;
          borderSide = BorderSide(color: Colors.red[200]!);
        } else {
          chipBg = Colors.white;
          textColor = Colors.black87;
          borderSide = BorderSide(color: Colors.grey[300]!);
        }

        return InkWell(
          onTap: isBooked
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${slot.format(context)} is already booked for ${_getBarberName()}.',
                        style: GoogleFonts.manrope(),
                      ),
                      backgroundColor: Colors.orange[800],
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              : () {
                  setState(() {
                    _selectedTime = slot;
                    _recheckConflict();
                  });
                },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.fromBorderSide(borderSide),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slot.format(context),
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: textColor,
                    decoration: isBooked ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (isBooked) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.lock, size: 12, color: Colors.red[400]),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSmallAvatar(String? photo, String name) {
    if (photo != null && photo.trim().isNotEmpty) {
      String clean = photo.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: ClipOval(
            child: Image.network(
              clean,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallbackSmallAvatar(name),
            ),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(
            base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: ClipOval(child: Image.memory(bytes, fit: BoxFit.cover)),
        );
      } catch (_) {}
    }
    return _buildFallbackSmallAvatar(name);
  }

  Widget _buildFallbackSmallAvatar(String name) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF5BBCFF),
      ),
      child: Center(
        child: Text(
          (name.isNotEmpty ? name[0] : 'B').toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
