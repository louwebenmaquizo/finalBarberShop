import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/booking_service.dart';
import '../../services/employee_service.dart';

class RescheduleScreen extends StatefulWidget {
  final Map<String, dynamic> booking;

  const RescheduleScreen({
    super.key,
    required this.booking,
  });

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _selectedStaffId;
  List<Map<String, dynamic>> _barbers = [];
  bool _isLoadingBarbers = true;
  bool _isSubmitting = false;

  // Color constants
  static const Color blueColor = Color(0xB25BBCFF); // #5BBCFFB2

  @override
  void initState() {
    super.initState();
    _loadBarbers();
    // Parse existing booking date and time
    _parseExistingBooking();
  }

  void _parseExistingBooking() {
    // Try to parse existing date
    final dateStr = widget.booking['date'] ?? '';
    if (dateStr.isNotEmpty) {
      try {
        // Assuming format like "Jan 15, 2024" or "2024-01-15"
        if (dateStr.contains(',')) {
          // Format: "Jan 15, 2024"
          final months = {
            'Jan': 1,
            'Feb': 2,
            'Mar': 3,
            'Apr': 4,
            'May': 5,
            'Jun': 6,
            'Jul': 7,
            'Aug': 8,
            'Sep': 9,
            'Oct': 10,
            'Nov': 11,
            'Dec': 12
          };
          final parts = dateStr.split(' ');
          if (parts.length >= 3) {
            final month = months[parts[0]] ?? 1;
            final day = int.tryParse(parts[1].replaceAll(',', '')) ?? 1;
            final year = int.tryParse(parts[2]) ?? DateTime.now().year;
            _selectedDate = DateTime(year, month, day);
          }
        } else {
          // Format: "2024-01-15"
          final parts = dateStr.split('-');
          if (parts.length == 3) {
            _selectedDate = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          }
        }
      } catch (_) {}
    }

    // Try to parse existing time
    final timeStr = widget.booking['time'] ?? '';
    if (timeStr.isNotEmpty) {
      try {
        // Assuming format like "2:30 PM" or "14:30"
        if (timeStr.contains('AM') || timeStr.contains('PM')) {
          final parts =
              timeStr.replaceAll(' AM', '').replaceAll(' PM', '').split(':');
          if (parts.length == 2) {
            var hour = int.parse(parts[0]);
            final minute = int.parse(parts[1]);
            if (timeStr.contains('PM') && hour != 12) hour += 12;
            if (timeStr.contains('AM') && hour == 12) hour = 0;
            _selectedTime = TimeOfDay(hour: hour, minute: minute);
          }
        } else {
          final parts = timeStr.split(':');
          if (parts.length >= 2) {
            _selectedTime = TimeOfDay(
              hour: int.parse(parts[0]),
              minute: int.parse(parts[1]),
            );
          }
        }
      } catch (_) {}
    }

    // Set existing staff if available
    final staffName = widget.booking['staff_name'] ?? '';
    if (staffName.isNotEmpty) {
      // Will be set after barbers load
    }
  }

  Future<void> _loadBarbers() async {
    setState(() {
      _isLoadingBarbers = true;
    });

    try {
      final barbers = await EmployeeService.getAllEmployees();

      // Filter only active barbers with role = "barber" - handle different is_active formats
      final activeBarbers = barbers.where((b) {
        // First check role - must be "barber" (case-insensitive)
        final role = (b['role'] ?? '').toString().toLowerCase();
        if (role != 'barber') return false;

        // Then check is_active
        final isActive = b['is_active'];
        // Handle boolean, int (1/0), or string ("1"/"0")
        if (isActive == null) return true; // Default to active if null
        if (isActive is bool) return isActive;
        if (isActive is int) return isActive == 1;
        if (isActive is String)
          return isActive == '1' || isActive.toLowerCase() == 'true';
        return true; // Default to active if unclear
      }).toList();

      if (activeBarbers.isEmpty && barbers.isNotEmpty) {
        // If all barbers are filtered out, show all of them
        setState(() {
          _barbers = barbers;
          _isLoadingBarbers = false;
        });
      } else {
        setState(() {
          _barbers = activeBarbers;
          _isLoadingBarbers = false;
        });
      }

      // Set selected staff if booking has staff_name
      final staffName = widget.booking['staff_name'] ?? '';
      if (staffName.isNotEmpty && _barbers.isNotEmpty) {
        try {
          final matchingBarber = _barbers.firstWhere(
            (b) => (b['name'] ?? '').toString() == staffName,
            orElse: () => {},
          );
          if (matchingBarber.isNotEmpty) {
            _selectedStaffId = matchingBarber['staff_id'];
          }
        } catch (_) {}
      }
    } catch (_) {
      setState(() {
        _isLoadingBarbers = false;
        _barbers = [];
      });
    }
  }

  Future<void> _selectDate() async {
    try {
      final now = DateTime.now();
      final firstDate = DateTime(now.year, now.month, now.day);

      // Ensure initial date is not before first date
      DateTime initialDate;
      if (_selectedDate != null && !_selectedDate!.isBefore(firstDate)) {
        initialDate = _selectedDate!;
      } else {
        initialDate = firstDate;
      }

      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: now.add(const Duration(days: 365)),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: blueColor,
                onPrimary: Colors.white,
                onSurface: Colors.black87,
              ),
            ),
            child: child ?? const SizedBox(),
          );
        },
      );
      if (picked != null && picked != _selectedDate) {
        setState(() {
          _selectedDate = picked;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error opening date picker: $e',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _selectTime() async {
    try {
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: _selectedTime ?? TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: blueColor,
                onPrimary: Colors.white,
                onSurface: Colors.black87,
              ),
            ),
            child: child ?? const SizedBox(),
          );
        },
      );
      if (picked != null && picked != _selectedTime) {
        setState(() {
          _selectedTime = picked;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error opening time picker: $e',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: Colors.red,
        ),
      );
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

  String _formatTime(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  String _formatDateForAPI(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTimeForAPI(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  }

  Future<void> _showConfirmationDialog() async {
    if (_selectedDate == null ||
        _selectedTime == null ||
        _selectedStaffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select date, time, and barber',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final selectedBarber = _barbers.firstWhere(
      (b) => b['staff_id'] == _selectedStaffId,
      orElse: () => {'name': 'Unknown'},
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: blueColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: blueColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              // Title
              Text(
                'Confirm Reschedule',
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              // Details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildConfirmationRow('Date', _formatDate(_selectedDate!)),
                    const SizedBox(height: 8),
                    _buildConfirmationRow('Time', _formatTime(_selectedTime!)),
                    const SizedBox(height: 8),
                    _buildConfirmationRow(
                        'Barber', selectedBarber['name'] ?? 'Unknown'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blueColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Confirm',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _submitReschedule();
    }
  }

  Widget _buildConfirmationRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitReschedule() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final appointmentId = widget.booking['appointment_id'] ?? '';
      final date = _formatDateForAPI(_selectedDate!);
      final time = _formatTimeForAPI(_selectedTime!);

      final result = await BookingService.rescheduleBooking(
        appointmentId,
        date,
        time,
        _selectedStaffId!,
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Booking rescheduled successfully',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // Return true to indicate success
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ??
                    result['error'] ??
                    'Failed to reschedule booking',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error rescheduling booking: $e',
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Reschedule Booking',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      body: _isSubmitting
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: blueColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.booking['customer_name'] ?? 'Unknown',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Date Selection
                  Text(
                    'Select Date',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _selectDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: blueColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedDate != null
                                  ? _formatDate(_selectedDate!)
                                  : 'Select date',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                color: _selectedDate != null
                                    ? Colors.black87
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              size: 16, color: Colors.grey[600]!),
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
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _selectTime,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, color: blueColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedTime != null
                                  ? _formatTime(_selectedTime!)
                                  : 'Select time',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                color: _selectedTime != null
                                    ? Colors.black87
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              size: 16, color: Colors.grey[600]!),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Barber Selection
                  Text(
                    'Select Barber',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _isLoadingBarbers
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _barbers.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Text(
                                  'No barbers available',
                                  style: GoogleFonts.manrope(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            )
                          : SizedBox(
                              height: 175,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _barbers.length,
                                itemBuilder: (context, index) {
                                  return _buildBarberCard(_barbers[index]);
                                },
                              ),
                            ),
                  const SizedBox(height: 32),

                  // Confirm Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _showConfirmationDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blueColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Reschedule Booking',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBarberCard(Map<String, dynamic> barber) {
    final isSelected = barber['staff_id'] == _selectedStaffId;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedStaffId = barber['staff_id'];
        });
      },
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? blueColor : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? blueColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: blueColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barber Image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/top_r_fes.jpg',
                width: 120,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 120,
                    height: 100,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withOpacity(0.3)
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.person,
                      size: 35,
                      color: isSelected ? Colors.white : Colors.grey[600],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // Barber Name
            Text(
              barber['name'] ?? 'Unknown',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.black : Colors.black87,
              ),
              textAlign: TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            // Barber Role
            Text(
              barber['role'] ?? 'N/A',
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: isSelected
                    ? Colors.white.withOpacity(0.9)
                    : Colors.grey[600],
              ),
              textAlign: TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
