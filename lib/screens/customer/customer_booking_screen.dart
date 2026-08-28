import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    // Pre-select service if provided
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
      // Load customer_id first
      await _loadCustomerId();

      // Load services and staff in parallel
      final results = await Future.wait([
        CatalogService.getAllServices(),
        EmployeeService.getAllEmployees(),
      ]);

      final services = results[0] as List<dynamic>;
      final employees = results[1] as List<dynamic>;

      // Filter services to only active ones
      final activeServices = services.where((s) {
        final isActive = s['is_active'];
        if (isActive is bool) return isActive;
        if (isActive is int) return isActive == 1;
        if (isActive is String)
          return isActive == '1' || isActive.toLowerCase() == 'true';
        return true; // Default to active if unclear
      }).toList();

      // Filter staff to only active barbers (exclude purely administrative roles)
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

      if (email.isEmpty && phone.isEmpty) return;

      final customers = await ApiService.getCustomers();

      // Find customer by email or phone
      for (var c in customers) {
        final cEmail = (c['email'] ?? '').toString().toLowerCase();
        final cPhone = (c['phone'] ?? '').toString();
        if ((email.isNotEmpty && cEmail == email.toLowerCase()) ||
            (phone.isNotEmpty && cPhone == phone)) {
          if (mounted) {
            setState(() {
              _customerId = c['customer_id'];
            });
          }
          break;
        }
      }
    } catch (_) {}
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
                primary: Color(0xB25BBCFF), // Blue
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
                primary: Color(0xB25BBCFF), // Blue
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

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
              backgroundColor: const Color(0xB25BBCFF),
            ),
            child: Text(
              'Confirm',
              style: GoogleFonts.manrope(color: Colors.white),
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
      // Get service to calculate duration
      Map<String, dynamic>? selectedService;
      for (var service in _services) {
        if (service['service_id'] == _selectedServiceId) {
          selectedService = service;
          break;
        }
      }

      if (selectedService == null) {
        throw Exception('Service not found');
      }

      // Parse duration_minutes - handle int, double, or String
      dynamic durationValue = selectedService['duration_minutes'] ?? 30;
      int durationMinutes = 30; // Default

      if (durationValue is int) {
        durationMinutes = durationValue;
      } else if (durationValue is double) {
        durationMinutes = durationValue.toInt();
      } else if (durationValue is String) {
        durationMinutes = int.tryParse(durationValue) ?? 30;
      } else if (durationValue is num) {
        durationMinutes = durationValue.toInt();
      }

      // Format date and time
      final dateStr =
          '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00';
      final startTime = '$dateStr $timeStr';

      // Calculate end_time
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

      // Create appointment
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
              content: Text(
                'Appointment booked successfully!',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // Return true to indicate success
        }
      } else {
        throw Exception('Failed to create appointment');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error booking appointment: ${e.toString()}',
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: Colors.red,
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Book Appointment',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Service Selection
                  Text(
                    'Select Service',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedServiceId,
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
                              return DropdownMenuItem<String>(
                                value: service['service_id'] as String?,
                                child: Text(
                                  service['name'] ?? 'Service',
                                  style: GoogleFonts.manrope(),
                                ),
                              );
                            }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedServiceId = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Staff Selection
                  Text(
                    'Select Barber',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedStaffId,
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
                                      style: GoogleFonts.manrope(fontSize: 14),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedStaffId = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Date Selection
                  Text(
                    'Select Date',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                                : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                            style: GoogleFonts.manrope(
                              color: _selectedDate == null
                                  ? Colors.grey[600]
                                  : Colors.black,
                            ),
                          ),
                          const Icon(Icons.calendar_today, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Time Selection
                  Text(
                    'Select Time',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _selectTime,
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
                            _selectedTime == null
                                ? 'Choose a time'
                                : _selectedTime!.format(context),
                            style: GoogleFonts.manrope(
                              color: _selectedTime == null
                                  ? Colors.grey[600]
                                  : Colors.black,
                            ),
                          ),
                          const Icon(Icons.access_time, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xB25BBCFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        disabledBackgroundColor: Colors.grey[300],
                      ),
                      child: _isSubmitting
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Book Appointment',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
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
