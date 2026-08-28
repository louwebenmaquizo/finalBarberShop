import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/booking_service.dart';
import '../../services/transaction_service.dart';
import '../../services/catalog_service.dart';
import 'reschedule_screen.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredBookings = [];
  List<Map<String, dynamic>> _allBookings = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _sortOrder = 'ascending'; // 'ascending' or 'descending'

  // Color constants matching dashboard
  static const Color blueColor = Color(0xB25BBCFF); // #5BBCFFB2
  static const Color pinkColor = Color(0xFFFBC0E6); // #FBC0E6

  @override
  void initState() {
    super.initState();
    _loadBookings();
    _searchController.addListener(_filterBookings);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterBookings);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final bookings = await BookingService.getAllBookings();
      // Filter out completed bookings
      final activeBookings = bookings.where((booking) {
        final status = booking['status'] ?? '';
        return status != 'completed';
      }).toList();
      
      setState(() {
        _allBookings = activeBookings;
        _filteredBookings = activeBookings;
        _isLoading = false;
      });
      // Apply initial sort
      _applySort(List.from(_filteredBookings));
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load bookings: $e';
        _isLoading = false;
      });
    }
  }

  void _filterBookings() {
    final query = _searchController.text;
    List<Map<String, dynamic>> filtered;
    
    // First, filter out completed bookings
    final activeBookings = _allBookings.where((booking) {
      final status = booking['status'] ?? '';
      return status != 'completed';
    }).toList();
    
    if (query.isEmpty) {
      filtered = List.from(activeBookings);
    } else {
      final searchQuery = query.toLowerCase();
      filtered = activeBookings.where((booking) {
        final customerName = (booking['customer_name'] ?? '').toLowerCase();
        final serviceName = (booking['service_name'] ?? '').toLowerCase();
        final staffName = (booking['staff_name'] ?? '').toLowerCase();
        final date = (booking['date'] ?? '').toLowerCase();
        final time = (booking['time'] ?? '').toLowerCase();
        
        return customerName.contains(searchQuery) || 
               serviceName.contains(searchQuery) || 
               staffName.contains(searchQuery) ||
               date.contains(searchQuery) ||
               time.contains(searchQuery);
      }).toList();
    }
    
    // Apply sorting
    _applySort(filtered);
  }
  
  void _applySort(List<Map<String, dynamic>> bookings) {
    bookings.sort((a, b) {
      // Parse date and time to create DateTime for comparison
      DateTime? dateTimeA = _parseBookingDateTime(a);
      DateTime? dateTimeB = _parseBookingDateTime(b);
      
      // Handle null dates (put them at the end)
      if (dateTimeA == null && dateTimeB == null) return 0;
      if (dateTimeA == null) return 1;
      if (dateTimeB == null) return -1;
      
      // Compare dates
      int comparison = dateTimeA.compareTo(dateTimeB);
      
      // Reverse if descending
      return _sortOrder == 'descending' ? -comparison : comparison;
    });
    
    setState(() {
      _filteredBookings = bookings;
    });
  }
  
  DateTime? _parseBookingDateTime(Map<String, dynamic> booking) {
    try {
      final dateStr = booking['date'] ?? '';
      final timeStr = booking['time'] ?? '';
      
      if (dateStr.isEmpty) return null;
      
      // Try to parse date (format: YYYY-MM-DD or similar)
      DateTime date;
      if (dateStr.contains('-')) {
        // Format: YYYY-MM-DD
        final dateParts = dateStr.split('-');
        if (dateParts.length >= 3) {
          date = DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
          );
        } else {
          return null;
        }
      } else {
        // Try other formats or return null
        return null;
      }
      
      // Parse time if available (format: HH:MM:SS or HH:MM)
      if (timeStr.isNotEmpty) {
        final timeParts = timeStr.split(':');
        if (timeParts.length >= 2) {
          date = DateTime(
            date.year,
            date.month,
            date.day,
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
          );
        }
      }
      
      return date;
    } catch (e) {
      print('Error parsing booking date/time: $e');
      return null;
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sort Bookings',
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Sort Order Section
                  Text(
                    'Sort Order',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Ascending Option
                  InkWell(
                    onTap: () {
                      setModalState(() {
                        _sortOrder = 'ascending';
                      });
                      setState(() {
                        _sortOrder = 'ascending';
                      });
                      _applySort(List.from(_filteredBookings));
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _sortOrder == 'ascending' 
                            ? blueColor.withOpacity(0.1) 
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _sortOrder == 'ascending' 
                              ? blueColor 
                              : Colors.grey[300]!,
                          width: _sortOrder == 'ascending' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_upward,
                            color: _sortOrder == 'ascending' 
                                ? blueColor 
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ascending',
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _sortOrder == 'ascending' 
                                        ? blueColor 
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Earliest to Latest',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_sortOrder == 'ascending')
                            Icon(
                              Icons.check_circle,
                              color: blueColor,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Descending Option
                  InkWell(
                    onTap: () {
                      setModalState(() {
                        _sortOrder = 'descending';
                      });
                      setState(() {
                        _sortOrder = 'descending';
                      });
                      _applySort(List.from(_filteredBookings));
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _sortOrder == 'descending' 
                            ? blueColor.withOpacity(0.1) 
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _sortOrder == 'descending' 
                              ? blueColor 
                              : Colors.grey[300]!,
                          width: _sortOrder == 'descending' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_downward,
                            color: _sortOrder == 'descending' 
                                ? blueColor 
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Descending',
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _sortOrder == 'descending' 
                                        ? blueColor 
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Latest to Earliest',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_sortOrder == 'descending')
                            Icon(
                              Icons.check_circle,
                              color: blueColor,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Fixed Header Section
          Container(
            padding: const EdgeInsets.all(23),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search bookings...',
                      hintStyle: GoogleFonts.manrope(
                        color: Colors.grey[500],
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.grey,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: GoogleFonts.manrope(),
                  ),
                ),
                const SizedBox(height: 14),

                // Next Client and Filter Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Next Client Text (left side)
                    Text(
                      'Next Client',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    // Filter Button (right side) - Text first, then icon
                    TextButton(
                      onPressed: () => _showFilterDialog(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Filter',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.filter_list,
                            size: 18,
                            color: Colors.black87,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Scrollable Bookings List
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 23),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 18),
                  _isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _errorMessage != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  children: [
                                    Text(
                                      _errorMessage!,
                                      style: GoogleFonts.manrope(
                                        color: Colors.red,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: _loadBookings,
                                      child: Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _filteredBookings.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32.0),
                                    child: Text(
                                      'No bookings found',
                                      style: GoogleFonts.manrope(
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _filteredBookings.length,
                                  itemBuilder: (context, index) {
                                    return _buildBookingCard(_filteredBookings[index]);
                                  },
                                ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromARGB(176, 67, 169, 241),
          width: 4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top section - Blue background
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: blueColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Name - Icon above, text below
                Expanded(
                  child: Column(
                    children: [
                      const Icon(Icons.person, color: Colors.white, size: 24),
                      const SizedBox(height: 8),
                      Text(
                        booking['customer_name'] ?? 'Unknown',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                // Date - Icon above, text below
                Expanded(
                  child: Column(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                      const SizedBox(height: 8),
                      Text(
                        booking['date'] ?? 'N/A',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                // Time - Icon above, text below
                Expanded(
                  child: Column(
                    children: [
                      const Icon(Icons.access_time, color: Colors.white, size: 20),
                      const SizedBox(height: 8),
                      Text(
                        booking['time'] ?? 'N/A',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Bottom section - White background with pink buttons
          Container(
            padding: const EdgeInsets.all(18),
            child: booking['status'] == 'completed'
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green, width: 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Completed',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : booking['status'] == 'pending'
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: _buildActionButton('Decline', Colors.red, () {
                              _handleDecline(booking);
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton('Accept', Colors.green, () {
                              _handleAccept(booking);
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton('Add Note', pinkColor, () {
                              _handleAddNote(booking);
                            }),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: _buildActionButton('Reschedule', pinkColor, () {
                              _handleReschedule(booking);
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton('Add Note', pinkColor, () {
                              _handleAddNote(booking);
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton('Complete', blueColor, () {
                              _handleComplete(booking);
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton('Delete', pinkColor, () {
                              _handleDelete(booking);
                            }),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _handleAccept(Map<String, dynamic> booking) async {
    final appointmentId = booking['appointment_id'];
    if (appointmentId == null || appointmentId.toString().isEmpty) return;

    try {
      final result = await BookingService.updateBooking(appointmentId.toString(), {'status': 'booked'});
      if (result['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking accepted and confirmed!', style: GoogleFonts.manrope()),
            backgroundColor: Colors.green,
          ),
        );
        _loadBookings();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting booking: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleDecline(Map<String, dynamic> booking) {
    final appointmentId = booking['appointment_id'];
    final customerName = booking['customer_name'] ?? 'Customer';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text('Decline Booking', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to decline the booking request from $customerName?',
          style: GoogleFonts.manrope(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.manrope(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final result = await BookingService.updateBooking(appointmentId.toString(), {'status': 'declined'});
                if (result['success'] == true && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Booking request declined', style: GoogleFonts.manrope()),
                      backgroundColor: Colors.red,
                    ),
                  );
                  _loadBookings();
                }
              } catch (_) {}
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Decline Request', style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleReschedule(Map<String, dynamic> booking) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RescheduleScreen(booking: booking),
      ),
    );
    
    // Reload bookings if reschedule was successful
    if (result == true) {
      _loadBookings();
    }
  }

  void _handleAddNote(Map<String, dynamic> booking) {
    final TextEditingController noteController = TextEditingController(
      text: booking['notes'] ?? '',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.note_alt_outlined, color: Color(0xFF1E88E5)),
            const SizedBox(width: 8),
            Text(
              'Add Appointment Note',
              style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer: ${booking['customer_name'] ?? 'Guest'} • ${booking['service_name'] ?? 'Service'}',
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'e.g. Skin fade #1 on sides, scissor cut on top, prefers mint aftershave...',
                hintStyle: GoogleFonts.manrope(fontSize: 13, color: Colors.grey[400]),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
            child: Text('Cancel', style: GoogleFonts.manrope(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                booking['notes'] = noteController.text.trim();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Note attached to booking!', style: GoogleFonts.manrope()),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5BBCFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Text(
              'Save Note',
              style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _handleComplete(Map<String, dynamic> booking) async {
    // Check if already completed
    if (booking['status'] == 'completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This booking is already completed',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show confirmation dialog
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
              // Success Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: blueColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: blueColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              // Title
              Text(
                'Complete Booking',
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              // Message
              Text(
                'Mark this booking as completed?\nThe status will be updated in the system.',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
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
                        'Complete',
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
      // Get full appointment details for transaction
      final appointmentDetails = await BookingService.getBookingById(
        booking['appointment_id'] ?? '',
      );

      if (appointmentDetails == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to load appointment details',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Check if required fields are present
      if (appointmentDetails['customer_id'] == null || 
          appointmentDetails['staff_id'] == null ||
          appointmentDetails['service_price'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Missing required appointment information',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Show payment dialog
      final paymentResult = await _showPaymentDialog(
        context,
        appointmentDetails,
      );

      if (paymentResult == null || paymentResult['cancelled'] == true) {
        return; // User cancelled payment
      }

      try {
        // Fetch service price from services table to ensure we use the current price
        double servicePrice = paymentResult['amount'] ?? 0.0;
        final serviceId = appointmentDetails['service_id'] ?? '';
        
        if (serviceId.isNotEmpty) {
          try {
            final service = await CatalogService.getServiceById(serviceId);
            if (service != null && service['price'] != null) {
              servicePrice = service['price'] is double
                  ? service['price']
                  : (service['price'] is String
                      ? double.tryParse(service['price']) ?? servicePrice
                      : (service['price'] is int
                          ? service['price'].toDouble()
                          : servicePrice));
            }
          } catch (e) {
            print('Error fetching service price for transaction: $e');
            // Use amount from payment dialog as fallback
          }
        }
        
        // Create transaction with service price from services table
        final transactionResult = await TransactionService.createTransaction(
          appointmentId: appointmentDetails['appointment_id'] ?? '',
          customerId: appointmentDetails['customer_id'] ?? '',
          amount: servicePrice,
          paymentMethod: paymentResult['payment_method'] ?? 'cash',
          staffId: appointmentDetails['staff_id'] ?? '',
          tipAmount: paymentResult['tip_amount'] ?? 0.0,
          taxAmount: paymentResult['tax_amount'] ?? 0.0,
        );

        if (transactionResult['success'] != true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  transactionResult['message'] ?? transactionResult['error'] ?? 'Failed to create transaction',
                  style: GoogleFonts.manrope(),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Complete the booking
        final result = await BookingService.completeBooking(
          booking['appointment_id'] ?? '',
        );

        if (mounted) {
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Booking completed and payment recorded',
                  style: GoogleFonts.manrope(),
                ),
                backgroundColor: Colors.green,
              ),
            );
            _loadBookings(); // Reload bookings to reflect status change
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result['message'] ?? result['error'] ?? 'Failed to complete booking',
                  style: GoogleFonts.manrope(),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error completing booking: $e',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _showPaymentDialog(
    BuildContext context,
    Map<String, dynamic> appointmentDetails,
  ) async {
    // Fetch service price from services table using service_id
    double baseAmount = 0.0;
    final serviceId = appointmentDetails['service_id'] ?? '';
    
    if (serviceId.isNotEmpty) {
      try {
        final service = await CatalogService.getServiceById(serviceId);
        if (service != null && service['price'] != null) {
          baseAmount = service['price'] is double
              ? service['price']
              : (service['price'] is String
                  ? double.tryParse(service['price']) ?? 0.0
                  : (service['price'] is int
                      ? service['price'].toDouble()
                      : 0.0));
        }
      } catch (e) {
        print('Error fetching service price: $e');
        // Fallback to service_price from appointment details if available
        baseAmount = appointmentDetails['service_price'] is double
            ? appointmentDetails['service_price']
            : (appointmentDetails['service_price'] is String
                ? double.tryParse(appointmentDetails['service_price']) ?? 0.0
                : 0.0);
      }
    } else {
      // Fallback if service_id is not available
      baseAmount = appointmentDetails['service_price'] is double
          ? appointmentDetails['service_price']
          : (appointmentDetails['service_price'] is String
              ? double.tryParse(appointmentDetails['service_price']) ?? 0.0
              : 0.0);
    }

    final tipController = TextEditingController(text: '0.00');
    final taxController = TextEditingController(text: '0.00');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // Use a mutable variable that will be properly captured in the closure
        final paymentMethodRef = <String>['cash']; // Use list to allow mutation in closure
        
        return StatefulBuilder(
          builder: (context, setState) {
            // Get current value from the ref
            String selectedPaymentMethod = paymentMethodRef[0];
            
            return AlertDialog(
              title: Text(
                'Complete Payment',
                style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // Service info
                      Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointmentDetails['service_name'] ?? 'Service',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Base Amount: \$${baseAmount.toStringAsFixed(2)}',
                        style: GoogleFonts.manrope(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Payment method
                Text(
                  'Payment Method',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedPaymentMethod,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: ['cash', 'card', 'mobile']
                      .map((method) => DropdownMenuItem(
                            value: method,
                            child: Text(
                              method.toUpperCase(),
                              style: GoogleFonts.manrope(),
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        paymentMethodRef[0] = value; // Update the ref
                      });
                    }
                  },
                ),
                const SizedBox(height: 20),
                
                // Tip amount
                Text(
                  'Tip Amount (Optional)',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tipController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {}); // Update total amount display
                  },
                ),
                const SizedBox(height: 16),
                
                // Tax amount
                Text(
                  'Tax Amount (Optional)',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: taxController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {}); // Update total amount display
                  },
                ),
                const SizedBox(height: 20),
                
                // Total amount - updates dynamically
                Builder(
                  builder: (context) {
                    final currentTip = double.tryParse(tipController.text) ?? 0.0;
                    final currentTax = double.tryParse(taxController.text) ?? 0.0;
                    final total = baseAmount + currentTip + currentTax;
                    
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: blueColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: blueColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            flex: 2,
                            child: Text(
                              'Total Amount:',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            flex: 1,
                            child: Text(
                              '\$${total.toStringAsFixed(2)}',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: blueColor,
                              ),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                tipController.dispose();
                taxController.dispose();
                Navigator.pop(context, {'cancelled': true});
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  color: Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                // Get final values from controllers
                final finalTip = double.tryParse(tipController.text) ?? 0.0;
                final finalTax = double.tryParse(taxController.text) ?? 0.0;
                final totalAmount = baseAmount + finalTip + finalTax;
                
                // Get the current payment method from the ref
                final paymentMethodValue = paymentMethodRef[0].isNotEmpty 
                    ? paymentMethodRef[0] 
                    : 'cash';
                
                print('Payment method being sent: $paymentMethodValue');
                
                tipController.dispose();
                taxController.dispose();
                Navigator.pop(context, {
                  'cancelled': false,
                  'amount': baseAmount,
                  'payment_method': paymentMethodValue,
                  'tip_amount': finalTip,
                  'tax_amount': finalTax,
                  'total_amount': totalAmount,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: blueColor,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Complete Payment',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
          },
        );
      },
    );

    return result;
  }

  void _handleDelete(Map<String, dynamic> booking) async {
    // Show confirmation modal
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
              // Warning Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.red,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              // Title
              Text(
                'Delete Booking',
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              // Message
              Text(
                'Are you sure you want to delete this booking?\nThis action cannot be undone.',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
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
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Delete',
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
      try {
        final result = await BookingService.deleteBooking(
          booking['appointment_id'] ?? '',
        );

        if (mounted) {
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Booking deleted successfully',
                  style: GoogleFonts.manrope(),
                ),
                backgroundColor: Colors.green,
              ),
            );
            _loadBookings(); // Reload bookings
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result['message'] ?? result['error'] ?? 'Failed to delete booking',
                  style: GoogleFonts.manrope(),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error deleting booking: $e',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

