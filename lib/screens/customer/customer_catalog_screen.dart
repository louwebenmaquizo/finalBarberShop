import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/catalog_service.dart';
import '../../services/employee_service.dart';
import 'customer_booking_screen.dart';
import 'customer_navigation_screen.dart';

class CustomerCatalogScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const CustomerCatalogScreen({super.key, this.userData});

  @override
  State<CustomerCatalogScreen> createState() => _CustomerCatalogScreenState();
}

class _CustomerCatalogScreenState extends State<CustomerCatalogScreen> {
  List<dynamic> _services = [];
  List<dynamic> _categories = [];
  List<dynamic> _barbers = [];
  bool _isLoading = true;
  String? _selectedCategoryId;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    _loadCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load categories, services, and barbers in parallel
      final results = await Future.wait([
        CatalogService.getAllCategories(),
        CatalogService.getAllServices(),
        EmployeeService.getAllEmployees(),
      ]);

      final categories = results[0] as List<dynamic>;
      final services = results[1] as List<dynamic>;
      final employees = results[2] as List<dynamic>;

      // Filter services to only active ones
      final activeServices = services.where((s) {
        final isActive = s['is_active'];
        if (isActive is bool) return isActive;
        if (isActive is int) return isActive == 1;
        if (isActive is String)
          return isActive == '1' || isActive.toLowerCase() == 'true';
        return true;
      }).toList();

      // Filter barbers to only active staff (exclude purely administrative roles)
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
        _categories = categories;
        _services = activeServices;
        _barbers = barbers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading catalog: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<dynamic> get _filteredServices {
    var filtered = _services;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((service) {
        final name = (service['name'] ?? '').toString().toLowerCase();
        final description =
            (service['description'] ?? '').toString().toLowerCase();
        final category =
            (service['category_name'] ?? '').toString().toLowerCase();
        return name.contains(query) ||
            description.contains(query) ||
            category.contains(query);
      }).toList();
    }

    // Filter by category
    if (_selectedCategoryId != null) {
      filtered = filtered.where((service) {
        return service['category_id'] == _selectedCategoryId;
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Services Catalog',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCatalog,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Section
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
                                hintText: 'Search services...',
                                hintStyle: GoogleFonts.manrope(
                                  color: Colors.grey[600],
                                ),
                                prefixIcon:
                                    Icon(Icons.search, color: Colors.grey[600]),
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

                          // Categories (Horizontal Scrollable)
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _buildCategoryChip(null, 'All'),
                                const SizedBox(width: 8),
                                ..._categories.map((category) => Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _buildCategoryChip(
                                        category['category_id'],
                                        category['name'] ?? 'Unknown',
                                      ),
                                    )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Popular Barber Section
                          Text(
                            'Popular Barber',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Barber Avatars
                          SizedBox(
                            height: 100,
                            child: _barbers.isEmpty
                                ? Center(
                                    child: Text(
                                      'No barbers available',
                                      style: GoogleFonts.manrope(
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _barbers.length,
                                    itemBuilder: (context, index) {
                                      final barber = _barbers[index];
                                      return _buildBarberAvatar(barber);
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),

                    // Services Section Title & All Services Grid
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Text(
                        'Services (${_filteredServices.length})',
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),

                    if (_filteredServices.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.store_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty ||
                                        _selectedCategoryId != null
                                    ? 'No services found'
                                    : 'No services available',
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount:
                                MediaQuery.of(context).size.width > 900
                                    ? 4
                                    : MediaQuery.of(context).size.width > 600
                                        ? 3
                                        : 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.80,
                          ),
                          itemCount: _filteredServices.length,
                          itemBuilder: (context, index) {
                            final service = _filteredServices[index];
                            return _buildServiceCard(service);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCategoryChip(String? categoryId, String name) {
    final isSelected = _selectedCategoryId == categoryId;
    return FilterChip(
      label: Text(name),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedCategoryId = selected ? categoryId : null;
        });
      },
      selectedColor: const Color(0xB25BBCFF),
      labelStyle: GoogleFonts.manrope(
        color: isSelected ? Colors.white : Colors.black,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildBarberAvatar(Map<String, dynamic> barber) {
    final name = barber['name'] ?? 'Barber';
    final photo = barber['profile_photo'] ??
        barber['photo'] ??
        barber['profile_picture'] ??
        barber['image_url'];
    return GestureDetector(
      onTap: () {
        _showBarberInfoModal(barber);
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            _buildBarberProfileImage(photo, name, 66, 22),
            const SizedBox(height: 8),
            // Barber Name
            Text(
              name,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarberProfileImage(
      String? photo, String name, double size, double fontSize) {
    if (photo != null && photo.trim().isNotEmpty) {
      String clean = photo.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return ClipOval(
          child: Image.network(
            clean,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _buildBarberInitialAvatar(name, size, fontSize),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(
            base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _buildBarberInitialAvatar(name, size, fontSize),
          ),
        );
      } catch (_) {}
    }
    return _buildBarberInitialAvatar(name, size, fontSize);
  }

  Widget _buildBarberInitialAvatar(String name, double size, double fontSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xB25BBCFF), // Blue
            Color(0xFFFBC0E6), // Pink
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'B',
          style: GoogleFonts.manrope(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _showBarberInfoModal(Map<String, dynamic> barber) {
    final photo = barber['profile_photo'] ??
        barber['photo'] ??
        barber['profile_picture'] ??
        barber['image_url'];
    final name = barber['name'] ?? 'Unknown';
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBarberProfileImage(photo, name, 90, 36),
              const SizedBox(height: 16),
              // Barber Name
              Text(
                name,
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              // Email
              _buildInfoRow(Icons.email, 'Email', barber['email'] ?? 'N/A'),
              const SizedBox(height: 12),
              // Role
              _buildInfoRow(Icons.work, 'Role', barber['role'] ?? 'N/A'),
              const SizedBox(height: 24),
              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xB25BBCFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Close',
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
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
              _buildCustomerCatalogImage(
                  service['image_url'] ?? service['photo'],
                  serviceName: name,
                  categoryName: categoryName),
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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

  static String getDefaultCatalogImage(String? name, [String? category]) {
    final n = (name ?? '').toLowerCase();
    final c = (category ?? '').toLowerCase();
    if (n.contains('classic')) return 'assets/catalog/1.png';
    if (n.contains('fade') || n.contains('skin')) return 'assets/catalog/2.jpg';
    if (n.contains('kid') || n.contains('child')) return 'assets/catalog/3.jpg';
    if (n.contains('styling') || n.contains('style') || c.contains('styling')) return 'assets/catalog/4.png';
    if ((n.contains('beard') && !n.contains('haircut')) || c.contains('beard')) return 'assets/catalog/5.jpg';
    if (n.contains('beard') || n.contains('package')) return 'assets/catalog/6.jpg';
    return 'assets/catalog/1.png';
  }

  Widget _buildCustomerCatalogImage(String? photo, {String? serviceName, String? categoryName}) {
    const double imgHeight = 108.0;
    String? clean = photo?.trim();
    if (clean == null || clean.isEmpty) {
      clean = getDefaultCatalogImage(serviceName, categoryName);
    }

    if (clean.startsWith('assets/')) {
      return Image.asset(
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
}
