import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../services/catalog_service.dart';
import '../../widgets/notifications_modal.dart';
import 'customer_catalog_screen.dart';
import 'customer_booking_screen.dart';
import 'customer_navigation_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const CustomerHomeScreen({super.key, this.userData});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  List<dynamic> _appointments = [];
  List<Map<String, dynamic>> _services = [];
  bool _isLoading = true;
  bool _isLoadingServices = true;
  String _customerName = 'Customer';
  String _customerPhone = '';
  String? _customerId;
  String? _customerPhoto;

  @override
  void initState() {
    super.initState();
    _loadCustomerData();
    _loadAppointments();
    _loadServices();
  }

  Future<void> _loadCustomerData() async {
    // Get customer name, phone, and photo from user data or customer record
    if (widget.userData != null) {
      final email = widget.userData!['email'] ?? '';
      final phone = widget.userData!['phone'] ?? '';
      final directId = widget.userData!['customer_id'];
      final photo = widget.userData!['profile_picture'] ??
          widget.userData!['profile_photo'];

      setState(() {
        if (directId != null && directId.toString().isNotEmpty) {
          _customerId = directId.toString();
        }
        if (photo != null && photo.toString().isNotEmpty) {
          _customerPhoto = photo.toString();
        }
        _customerName = widget.userData!['full_name'] ??
            widget.userData!['username'] ??
            (email.isNotEmpty ? email.split('@')[0] : 'Customer');
        _customerPhone = phone;
      });

      // Look up customer by email or phone to get latest profile_picture if needed
      try {
        final customers = await ApiService.getCustomers();
        Map<String, dynamic>? customer;

        for (var c in customers) {
          final cEmail = (c['email'] ?? '').toString().toLowerCase();
          final cPhone = (c['phone'] ?? '').toString();
          final cId = (c['customer_id'] ?? '').toString();
          if ((_customerId != null && cId == _customerId) ||
              (email.isNotEmpty && cEmail == email.toLowerCase()) ||
              (phone.isNotEmpty && cPhone == phone)) {
            customer = c as Map<String, dynamic>?;
            break;
          }
        }

        if (customer != null && customer['customer_id'] != null) {
          if (mounted) {
            setState(() {
              _customerId = customer!['customer_id'];
              if (_customerPhone.isEmpty && customer['phone'] != null) {
                _customerPhone = customer['phone'].toString();
              }
              if (customer['full_name'] != null) {
                _customerName = customer['full_name'].toString();
              }
              if (customer['profile_picture'] != null &&
                  customer['profile_picture'].toString().isNotEmpty) {
                _customerPhoto = customer['profile_picture'].toString();
              }
            });
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load customer_id first if not already loaded
      if (_customerId == null && widget.userData != null) {
        await _loadCustomerData();
      }

      // Get appointments filtered by customer_id and upcoming only (no past appointments)
      final appointments = await ApiService.getAppointments(
        customerId: _customerId,
        upcomingOnly: true, // Only get upcoming appointments from today onwards
      );

      // Additional frontend filter to ensure no past appointments slip through
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final upcomingAppointments = appointments.where((apt) {
        try {
          final status = (apt['status'] ?? '').toString().toLowerCase();
          if (status == 'canceled' ||
              status == 'cancelled' ||
              status == 'completed') {
            return false;
          }
          if (apt['start_time'] != null) {
            try {
              final startTimeStr = apt['start_time'].toString();
              DateTime? appointmentDate;
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
                final apptDay = DateTime(appointmentDate.year,
                    appointmentDate.month, appointmentDate.day);
                return !apptDay.isBefore(today);
              }
            } catch (_) {}
          }
          return false;
        } catch (_) {
          return false;
        }
      }).toList();

      if (mounted) {
        setState(() {
          _appointments = upcomingAppointments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading appointments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadServices() async {
    setState(() {
      _isLoadingServices = true;
    });

    try {
      final services = await CatalogService.getAllServices();
      if (mounted) {
        setState(() {
          _services = services.where((service) {
            final isActive = service['is_active'];
            if (isActive is int) {
              return isActive == 1;
            }
            if (isActive is bool) {
              return isActive == true;
            }
            if (isActive is String) {
              return isActive == '1' || isActive.toLowerCase() == 'true';
            }
            return true;
          }).toList();
          _isLoadingServices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingServices = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading services: $e'),
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
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              _loadAppointments(),
              _loadServices(),
            ]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Section
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Avatar & Actions
                      Row(
                        children: [
                          _buildCustomerProfileAvatar(
                              _customerPhoto, _customerName,
                              size: 56),
                          const Spacer(),
                          // Notification Icon
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.notifications_outlined,
                                  size: 20, color: Colors.black87),
                              onPressed: () => showNotificationsModal(context,
                                  isAdmin: false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Search / Catalog Icon
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.search,
                                  size: 20, color: Colors.black87),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CustomerCatalogScreen(
                                        userData: widget.userData),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Greetings & Customer Name
                      Text(
                        _customerName.isNotEmpty
                            ? _customerName
                            : 'Hello, Welcome!',
                        style: GoogleFonts.manrope(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_customerPhone.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.phone,
                                size: 15, color: Colors.grey[600]),
                            const SizedBox(width: 6),
                            Text(
                              _customerPhone,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),

                      // Appointment Section Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Appointment',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          if (_appointments.isNotEmpty && !_isLoading)
                            Text(
                              _getAppointmentDateLabel(_appointments.first),
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Appointment Card with Gradient
                      if (_appointments.isNotEmpty && !_isLoading)
                        _buildAppointmentHeaderCard(_appointments.first)
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFBC0E6), // Pink
                                Color(0xB25BBCFF), // Blue
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    const Color(0xB25BBCFF).withOpacity(0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_available,
                                  color: Colors.white, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'No upcoming appointments',
                                      style: GoogleFonts.manrope(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Book your next haircut in seconds below',
                                      style: GoogleFonts.manrope(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Services Header Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Services',
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_services.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0x1A5BBCFF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_services.length}',
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1E88E5),
                                ),
                              ),
                            ),
                        ],
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CustomerCatalogScreen(
                                  userData: widget.userData),
                            ),
                          );
                        },
                        child: Text(
                          'See All',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E88E5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ALL Services Grid - Dynamically displaying all available services
                if (_isLoadingServices)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_services.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: Text(
                        'No services available',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: _services.length,
                      itemBuilder: (context, index) {
                        return _buildServiceCard(_services[index]);
                      },
                    ),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppointmentHeaderCard(Map<String, dynamic> appointment) {
    // Parse date and time from appointment
    final dateStr = appointment['date'] ?? '';
    final timeStr = appointment['time'] ?? '';
    final serviceName = appointment['service_name'] ?? 'Service';
    final description = appointment['description'] ?? '';
    final category =
        appointment['category_name'] ?? appointment['category'] ?? '';
    final price =
        appointment['price'] ?? appointment['service_price'] ?? '0.00';
    final serviceImage =
        appointment['service_image'] ?? appointment['image_url'];

    return Stack(
      children: [
        // Main gradient container
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFBC0E6), // Pink
                Color(0xB25BBCFF), // Blue
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service Image (Left side)
              _buildAppointmentServiceImage(serviceImage,
                  width: 70, height: 70),
              const SizedBox(width: 12),
              // Right side: Service name, Description, Category, Time and Price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Service Name
                    Text(
                      serviceName,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Description
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    // Category & Status Row
                    Row(
                      children: [
                        if (category.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              category,
                              style: GoogleFonts.manrope(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if ((appointment['status'] ?? '')
                                .toString()
                                .toLowerCase() ==
                            'pending') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange[800],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'PENDING APPROVAL',
                              style: GoogleFonts.manrope(
                                fontSize: 8.5,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Time and Price (inside rectangle, left side)
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeStr.isNotEmpty ? timeStr : 'N/A',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '\$${price.toString()}',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Date outside rectangle in upper right corner
        if (dateStr.isNotEmpty)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                dateStr,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xB25BBCFF),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _getAppointmentDateLabel(Map<String, dynamic> appointment) {
    try {
      DateTime? appointmentDate;
      if (appointment['start_time'] != null) {
        try {
          final startTimeStr = appointment['start_time'].toString();
          if (startTimeStr.contains('T')) {
            appointmentDate = DateTime.tryParse(startTimeStr);
          } else {
            final parts = startTimeStr.split(' ');
            if (parts.length == 2) {
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
        } catch (_) {}
      }
      if (appointmentDate == null && appointment['date'] != null) {
        try {
          final dateStr = appointment['date'].toString();
          final dateParts = dateStr.replaceAll(',', '').split(' ');
          if (dateParts.length == 3) {
            final monthMap = {
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
            final month = monthMap[dateParts[0]];
            final day = int.tryParse(dateParts[1]);
            final year = int.tryParse(dateParts[2]);
            if (month != null && day != null && year != null) {
              appointmentDate = DateTime(year, month, day);
            }
          }
        } catch (_) {}
      }
      if (appointmentDate == null) return '';
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final appointmentDay = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );
      final difference = appointmentDay.difference(today).inDays;
      if (difference == 0) return 'Today';
      if (difference == 1) return 'Tomorrow';
      return difference > 1 ? '$difference days left' : '';
    } catch (_) {
      return '';
    }
  }

  String _formatPrice(double price) {
    if (price == price.roundToDouble()) {
      return '\$${price.toInt()}';
    }
    return '\$${price.toStringAsFixed(2)}';
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final name = service['name'] ?? 'Service';
    final description = service['description'] ?? '';
    final categoryName = service['category_name'] ?? '';
    final durationMinutes = service['duration_minutes'] ?? 30;

    final priceValue = service['price'];
    double price = 0.0;
    if (priceValue is int) {
      price = priceValue.toDouble();
    } else if (priceValue is double) {
      price = priceValue;
    } else if (priceValue is String) {
      price = double.tryParse(priceValue) ?? 0.0;
    } else if (priceValue is num) {
      price = priceValue.toDouble();
    }

    final rating = 4.9;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service Image with Overlays
          Stack(
            children: [
              _buildCustomerServiceImage(
                  service['image_url'] ?? service['photo']),
              // Category Pill
              if (categoryName.isNotEmpty)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      categoryName.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              // Rating Badge
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 11, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        rating.toStringAsFixed(1),
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Card Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (description.isNotEmpty)
                        Text(
                          description,
                          style: GoogleFonts.manrope(
                            fontSize: 10.5,
                            color: Colors.grey[600],
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        Text(
                          '$durationMinutes mins session',
                          style: GoogleFonts.manrope(
                            fontSize: 10.5,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),

                  // Price and Book Button Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _formatPrice(price),
                        style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F8751),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CustomerBookingScreen(
                                userData: widget.userData,
                                preSelectedService: service,
                              ),
                            ),
                          );
                          if (result == true && mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CustomerNavigationScreen(
                                  userData: widget.userData,
                                  initialIndex: 2,
                                ),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5BBCFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 0),
                          minimumSize: const Size(60, 26),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Book Now',
                          style: GoogleFonts.manrope(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
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

  Widget _buildCustomerServiceImage(String? photo) {
    const double imgHeight = 125.0;
    if (photo == null || photo.isEmpty) {
      return Container(
        height: imgHeight,
        width: double.infinity,
        color: const Color(0x1A5BBCFF),
        child:
            const Icon(Icons.content_cut, size: 36, color: Color(0xFF5BBCFF)),
      );
    }

    final clean = photo.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return Image.network(
        clean,
        height: imgHeight,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: imgHeight,
          width: double.infinity,
          color: const Color(0x1A5BBCFF),
          child:
              const Icon(Icons.content_cut, size: 36, color: Color(0xFF5BBCFF)),
        ),
      );
    }

    try {
      final base64Data = clean.contains(',') ? clean.split(',').last : clean;
      final bytes = base64Decode(
          base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
      return Image.memory(
        bytes,
        height: imgHeight,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: imgHeight,
          width: double.infinity,
          color: const Color(0x1A5BBCFF),
          child:
              const Icon(Icons.content_cut, size: 36, color: Color(0xFF5BBCFF)),
        ),
      );
    } catch (_) {
      return Container(
        height: imgHeight,
        width: double.infinity,
        color: const Color(0x1A5BBCFF),
        child:
            const Icon(Icons.content_cut, size: 36, color: Color(0xFF5BBCFF)),
      );
    }
  }

  Widget _buildAppointmentServiceImage(String? photo,
      {double width = 70, double height = 70, BorderRadius? borderRadius}) {
    final radius = borderRadius ?? BorderRadius.circular(8);
    if (photo != null && photo.trim().isNotEmpty) {
      String clean = photo.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return ClipRRect(
          borderRadius: radius,
          child: Image.network(
            clean,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _buildFallbackServiceImage(width, height, radius),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(
            base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return ClipRRect(
          borderRadius: radius,
          child: Image.memory(
            bytes,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _buildFallbackServiceImage(width, height, radius),
          ),
        );
      } catch (_) {}
    }
    return _buildFallbackServiceImage(width, height, radius);
  }

  Widget _buildFallbackServiceImage(
      double width, double height, BorderRadius radius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.3),
        borderRadius: radius,
      ),
      child: const Icon(Icons.content_cut, color: Colors.white, size: 28),
    );
  }

  Widget _buildCustomerProfileAvatar(String? photo, String name,
      {double size = 56}) {
    if (photo != null && photo.trim().isNotEmpty) {
      String clean = photo.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF5BBCFF), width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              clean,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _buildCustomerFallbackAvatar(name, size),
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
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF5BBCFF), width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        );
      } catch (_) {}
    }
    return _buildCustomerFallbackAvatar(name, size);
  }

  Widget _buildCustomerFallbackAvatar(String name, double size) {
    final initial =
        (name.trim().isNotEmpty ? name.trim()[0] : 'C').toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0x1A5BBCFF),
        border: Border.all(color: const Color(0xFF5BBCFF), width: 1.5),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.manrope(
            fontSize: size * 0.42,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E88E5),
          ),
        ),
      ),
    );
  }
}
