import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/employee_service.dart';
import 'employee_detail_screen.dart';
import 'add_employee_screen.dart';

class EmployeeScreen extends StatefulWidget {
  const EmployeeScreen({super.key});

  @override
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredEmployees = [];
  List<Map<String, dynamic>> _allEmployees = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _statusFilter =
      'active'; // 'active' = active only (default), 'inactive' = inactive only
  String? _selectedRole; // Selected role filter (null = all roles)

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchController.addListener(_filterEmployees);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterEmployees);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final employees = await EmployeeService.getAllEmployees();
      setState(() {
        _allEmployees = employees;
        _filteredEmployees = employees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load employees: $e';
        _isLoading = false;
      });
    }
  }

  void _filterEmployees() {
    final query = _searchController.text;

    // First filter by status (is_active)
    // Schema: is_active = 1 for active, 0 for inactive
    List<Map<String, dynamic>> statusFiltered = _allEmployees;
    if (_statusFilter == 'active') {
      statusFiltered = _allEmployees.where((employee) {
        final isActive = employee['is_active'];
        // Handle integer: 1 = active, 0 = inactive
        if (isActive is int) {
          return isActive == 1;
        }
        // Handle boolean (backward compatibility)
        if (isActive is bool) {
          return isActive == true;
        }
        // Handle string representation
        if (isActive is String) {
          return isActive == '1' || isActive.toLowerCase() == 'true';
        }
        // Default to active if unclear
        return true;
      }).toList();
    } else if (_statusFilter == 'inactive') {
      statusFiltered = _allEmployees.where((employee) {
        final isActive = employee['is_active'];
        // Handle integer: 1 = active, 0 = inactive
        if (isActive is int) {
          return isActive == 0;
        }
        // Handle boolean (backward compatibility)
        if (isActive is bool) {
          return isActive == false;
        }
        // Handle string representation
        if (isActive is String) {
          return isActive == '0' || isActive.toLowerCase() == 'false';
        }
        // Default to inactive if unclear
        return false;
      }).toList();
    }

    // Then filter by role
    List<Map<String, dynamic>> roleFiltered = statusFiltered;
    if (_selectedRole != null) {
      roleFiltered = statusFiltered.where((employee) {
        return employee['role'] == _selectedRole;
      }).toList();
    }

    // Then filter by search query
    if (query.isEmpty) {
      setState(() {
        _filteredEmployees = roleFiltered;
      });
    } else {
      final searchQuery = query.toLowerCase();
      setState(() {
        _filteredEmployees = roleFiltered.where((employee) {
          final name = (employee['name'] ?? '').toLowerCase();
          final role = (employee['role'] ?? '').toLowerCase();
          return name.contains(searchQuery) || role.contains(searchQuery);
        }).toList();
      });
    }
  }

  void _setStatusFilter(String? filter) {
    setState(() {
      _statusFilter = filter;
    });
    _filterEmployees();
  }

  void _showRoleFilterDialog() {
    // Get unique roles from employees
    final roles = _allEmployees
        .map((e) => e['role'] as String?)
        .where((role) => role != null && role.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Filter by Role',
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
              const SizedBox(height: 16),
              // All Roles option
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Radio<String?>(
                  value: null,
                  groupValue: _selectedRole,
                  onChanged: (value) {
                    setState(() {
                      _selectedRole = value;
                    });
                    _filterEmployees();
                    Navigator.pop(context);
                  },
                ),
                title: Text(
                  'All Roles',
                  style: GoogleFonts.manrope(
                    fontWeight: _selectedRole == null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  setState(() {
                    _selectedRole = null;
                  });
                  _filterEmployees();
                  Navigator.pop(context);
                },
              ),
              // Role list
              ...roles.map((role) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Radio<String?>(
                    value: role,
                    groupValue: _selectedRole,
                    onChanged: (value) {
                      setState(() {
                        _selectedRole = value;
                      });
                      _filterEmployees();
                      Navigator.pop(context);
                    },
                  ),
                  title: Text(
                    role ?? '',
                    style: GoogleFonts.manrope(
                      fontWeight: _selectedRole == role
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _selectedRole = role;
                    });
                    _filterEmployees();
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
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
                // Employee Title
                Text(
                  'Employee',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),

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
                      hintText: 'Search employees...',
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
                const SizedBox(height: 24),

                // Active/Inactive Filter Buttons
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _setStatusFilter('active'),
                          child: Container(
                            height: 30,
                            decoration: BoxDecoration(
                              color: _statusFilter == 'active'
                                  ? Colors.black
                                  : Colors.white,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(11),
                                bottomLeft: Radius.circular(11),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Active Employees',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _statusFilter == 'active'
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _setStatusFilter('inactive'),
                          child: Container(
                            height: 30,
                            decoration: BoxDecoration(
                              color: _statusFilter == 'inactive'
                                  ? Colors.black
                                  : Colors.white,
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(11),
                                bottomRight: Radius.circular(11),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Inactive Employees',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _statusFilter == 'inactive'
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Filter Button (left side)
                TextButton(
                  onPressed: () => _showRoleFilterDialog(),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          ),

          // Scrollable Employee List
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 23),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 18),
                  // Employee List
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
                                      onPressed: _loadEmployees,
                                      child: Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _filteredEmployees.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32.0),
                                    child: Text(
                                      'No employees found',
                                      style: GoogleFonts.manrope(
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _filteredEmployees.length,
                                  itemBuilder: (context, index) {
                                    return _buildEmployeeItem(
                                        _filteredEmployees[index]);
                                  },
                                ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 68.0),
        child: FloatingActionButton(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AddEmployeeScreen(),
              ),
            );

            // Refresh list if employee was added
            if (result == true) {
              _loadEmployees();
            }
          },
          backgroundColor: Colors.black,
          shape: const CircleBorder(),
          child: const Icon(
            Icons.add,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeItem(Map<String, dynamic> employee) {
    final isActive = employee['is_active'] == true ||
        employee['is_active'] == 1 ||
        employee['is_active'] == '1';

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EmployeeDetailScreen(
              staffId: employee['staff_id'] ?? '',
              name: employee['name'],
              role: employee['role'],
            ),
          ),
        );
        // Always auto-refresh employee list after viewing or editing
        _loadEmployees();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.grey[200]! : Colors.red[200]!,
            width: isActive ? 1 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Circle Avatar with photo or gradient initial
            _buildBarberAvatar(
                employee['profile_photo'], employee['name'] ?? 'B'),
            const SizedBox(width: 16),
            // Name, Role, and Active/Inactive Badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          employee['name'] ?? 'Unknown',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Inactive',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    employee['role'] ?? 'N/A',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 22,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarberAvatar(String? photo, String name) {
    if (photo != null && photo.trim().isNotEmpty) {
      final clean = photo.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF5BBCFF), width: 1.5),
          ),
          child: ClipOval(
            child: Image.network(
              clean,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallbackInitial(name),
            ),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final cleanBase64 =
            base64Data.replaceAll('\n', '').replaceAll('\r', '').trim();
        final bytes = base64Decode(cleanBase64);
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF5BBCFF), width: 1.5),
          ),
          child: ClipOval(
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallbackInitial(name),
            ),
          ),
        );
      } catch (_) {}
    }
    return _buildFallbackInitial(name);
  }

  Widget _buildFallbackInitial(String name) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xB25BBCFF),
            Color.fromARGB(177, 194, 221, 240),
            Color.fromARGB(255, 253, 163, 208),
          ],
        ),
      ),
      child: Center(
        child: Text(
          (name.isNotEmpty ? name[0] : 'B').toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
