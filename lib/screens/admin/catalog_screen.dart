import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/catalog_service.dart';
import '../../widgets/category_dialogs.dart';
import 'service_detail_screen.dart';
import 'add_service_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredServices = [];
  List<Map<String, dynamic>> _allServices = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _statusFilter = 'active'; // 'active' = active only, 'inactive' = inactive only
  String? _selectedCategoryId; // Selected category filter (null = all categories)
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadServices();
    _loadCategories();
    _searchController.addListener(_filterServices);
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await CatalogService.getAllCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
        });
      }
    } catch (e) {
      print('Error loading categories: $e');
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterServices);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final services = await CatalogService.getAllServices();
      setState(() {
        _allServices = services;
        _isLoading = false;
      });
      _filterServices();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load services: $e';
        _isLoading = false;
      });
    }
  }

  void _filterServices() {
    final query = _searchController.text.trim().toLowerCase();
    
    // 1. Filter by active/inactive status
    List<Map<String, dynamic>> statusFiltered = _allServices;
    if (_statusFilter == 'active') {
      statusFiltered = _allServices.where((service) {
        final isActive = service['is_active'];
        if (isActive is int) return isActive == 1;
        if (isActive is bool) return isActive == true;
        if (isActive is String) return isActive == '1' || isActive.toLowerCase() == 'true';
        return true;
      }).toList();
    } else if (_statusFilter == 'inactive') {
      statusFiltered = _allServices.where((service) {
        final isActive = service['is_active'];
        if (isActive is int) return isActive == 0;
        if (isActive is bool) return isActive == false;
        if (isActive is String) return isActive == '0' || isActive.toLowerCase() == 'false';
        return false;
      }).toList();
    }

    // 2. Filter by category
    List<Map<String, dynamic>> categoryFiltered = statusFiltered;
    if (_selectedCategoryId != null) {
      categoryFiltered = statusFiltered.where((service) {
        return service['category_id'] == _selectedCategoryId;
      }).toList();
    }

    // 3. Filter by search query
    if (query.isEmpty) {
      setState(() {
        _filteredServices = categoryFiltered;
      });
    } else {
      setState(() {
        _filteredServices = categoryFiltered.where((service) {
          final name = (service['name'] ?? '').toString().toLowerCase();
          final description = (service['description'] ?? '').toString().toLowerCase();
          final categoryName = (service['category_name'] ?? '').toString().toLowerCase();
          return name.contains(query) || description.contains(query) || categoryName.contains(query);
        }).toList();
      });
    }
  }

  void _showAddCategory() async {
    final created = await showAddCategoryDialog(
      context,
      onCategoryCreated: (newCat) {
        _loadCategories();
        setState(() {
          _selectedCategoryId = newCat['category_id'];
        });
        _filterServices();
      },
    );
    if (created != null) {
      _loadCategories();
      setState(() {
        _selectedCategoryId = created['category_id'];
      });
      _filterServices();
    }
  }

  void _showManageCategories() {
    showManageCategoriesDialog(
      context,
      onChanged: () {
        _loadCategories();
        _loadServices();
      },
    );
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add to Catalog',
                style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0x1A5BBCFF), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.content_cut, color: Color(0xFF1E88E5)),
                ),
                title: Text('Add New Service', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
                subtitle: Text('Create a haircut, shave, or styling package', style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey[600])),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AddServiceScreen()),
                  );
                  if (result == true) {
                    _loadServices();
                    _loadCategories();
                  }
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.category, color: Colors.purple),
                ),
                title: Text('Add New Category', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
                subtitle: Text('Group services into clean custom categories', style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey[600])),
                onTap: () {
                  Navigator.pop(context);
                  _showAddCategory();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.tune, color: Colors.amber[800]),
                ),
                title: Text('Manage Categories', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
                subtitle: Text('Rename, edit, or delete existing categories', style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey[600])),
                onTap: () {
                  Navigator.pop(context);
                  _showManageCategories();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setStatusFilter(String? filter) {
    setState(() {
      _statusFilter = filter;
    });
    _filterServices();
  }

  Widget _buildCategoryChip(String? categoryId, String name, {int count = 0}) {
    final isSelected = _selectedCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name),
            if (count > 0 && categoryId != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.3) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ],
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedCategoryId = selected ? categoryId : null;
          });
          _filterServices();
        },
        selectedColor: const Color(0xFF5BBCFF),
        labelStyle: GoogleFonts.manrope(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
        backgroundColor: Colors.grey[100],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildCategoryHorizontalBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // All chip
          _buildCategoryChip(null, 'All'),
          // Dynamic category chips
          ..._categories.map((cat) {
            return _buildCategoryChip(
              cat['category_id'],
              cat['name'] ?? 'Category',
              count: cat['service_count'] ?? 0,
            );
          }),
          // Add Category chip
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 16, color: Color(0xFF1E88E5)),
              label: Text(
                'Add Category',
                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E88E5)),
              ),
              backgroundColor: const Color(0x1A5BBCFF),
              side: const BorderSide(color: Color(0xFF5BBCFF)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onPressed: _showAddCategory,
            ),
          ),
          // Manage button
          IconButton(
            icon: const Icon(Icons.tune, size: 18, color: Colors.grey),
            tooltip: 'Manage Categories',
            onPressed: _showManageCategories,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMenu,
        backgroundColor: Colors.black,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Add',
          style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadCategories();
          await _loadServices();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
                          hintText: 'Search services, categories...',
                          hintStyle: GoogleFonts.manrope(color: Colors.grey[500]),
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        style: GoogleFonts.manrope(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Active / Inactive Toggle
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!, width: 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _setStatusFilter('active'),
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _statusFilter == 'active' ? Colors.black : Colors.white,
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(9)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Active Services',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _statusFilter == 'active' ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _setStatusFilter('inactive'),
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _statusFilter == 'inactive' ? Colors.black : Colors.white,
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Inactive Services',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _statusFilter == 'inactive' ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Horizontal Category Filter Bar with "+ Add Category"
                    _buildCategoryHorizontalBar(),
                  ],
                ),
              ),
              
              // All Services Grid
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_errorMessage != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            children: [
                              Text(_errorMessage!, style: GoogleFonts.manrope(color: Colors.red), textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(onPressed: _loadServices, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    else if (_filteredServices.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Column(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'No Services Found',
                                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedCategoryId != null
                                    ? 'No services under this category.'
                                    : 'Add a service to get started.',
                                style: GoogleFonts.manrope(fontSize: 13, color: Colors.grey[500]),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const AddServiceScreen()),
                                  );
                                  if (result == true) {
                                    _loadServices();
                                    _loadCategories();
                                  }
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add Service'),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5BBCFF)),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.82,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _filteredServices.length,
                        itemBuilder: (context, index) {
                          return _buildServiceItem(_filteredServices[index]);
                        },
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

  Widget _buildServiceItem(Map<String, dynamic> service) {
    final serviceName = service['name'] ?? 'Service';
    final description = service['description'] ?? '';
    final categoryName = service['category_name'] ?? '';
    final price = double.tryParse((service['price'] ?? 0).toString()) ?? 0.0;
    final photo = service['photo'] ?? service['image_url'];

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ServiceDetailScreen(
              serviceId: service['service_id'] ?? '',
              name: serviceName,
            ),
          ),
        );
        if (result == true) {
          _loadServices();
          _loadCategories();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service Image / Category Banner
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0x0D5BBCFF),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                ),
                child: _buildCatalogImage(photo),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (categoryName.isNotEmpty)
                    Text(
                      categoryName.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E88E5),
                      ),
                      maxLines: 1,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    serviceName,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatPrice(price),
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F8751),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_outlined, size: 14, color: Colors.black87),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    if (price == price.roundToDouble()) {
      return '\$${price.toInt()}';
    }
    return '\$${price.toStringAsFixed(2)}';
  }

  Widget _buildCatalogImage(String? photo) {
    if (photo == null || photo.isEmpty) {
      return const Center(
        child: Icon(Icons.content_cut, size: 36, color: Color(0xFF5BBCFF)),
      );
    }
    
    final clean = photo.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
        child: Image.network(
          clean,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.content_cut, size: 36, color: Color(0xFF5BBCFF)),
          ),
        ),
      );
    }

    try {
      final base64Data = clean.contains(',') ? clean.split(',').last : clean;
      final bytes = base64Decode(base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.content_cut, size: 36, color: Color(0xFF5BBCFF)),
          ),
        ),
      );
    } catch (_) {
      return const Center(
        child: Icon(Icons.content_cut, size: 36, color: Color(0xFF5BBCFF)),
      );
    }
  }
}
