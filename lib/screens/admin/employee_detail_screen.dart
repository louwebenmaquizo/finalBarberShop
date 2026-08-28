import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/employee_service.dart';

class EmployeeDetailScreen extends StatefulWidget {
  final String staffId;
  final String? name;
  final String? role;

  const EmployeeDetailScreen({
    super.key,
    required this.staffId,
    this.name,
    this.role,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();
  final TextEditingController _skillsController = TextEditingController();
  final TextEditingController _payRateController = TextEditingController();
  final TextEditingController _commissionRateController = TextEditingController();
  bool _isActive = true;
  String? _profilePhoto;
  Uint8List? _newPhotoBytes;

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _roleController.dispose();
    _skillsController.dispose();
    _payRateController.dispose();
    _commissionRateController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final base64Str = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        setState(() {
          _newPhotoBytes = bytes;
          _profilePhoto = base64Str;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _loadEmployeeData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final employee = await EmployeeService.getEmployeeById(widget.staffId);

      if (employee != null && employee.isNotEmpty) {
        setState(() {
          _nameController.text = employee['name'] ?? '';
          _phoneController.text = employee['phone'] ?? '';
          _emailController.text = employee['email'] ?? '';
          _roleController.text = employee['role'] ?? '';
          _skillsController.text = employee['skills'] ?? '';
          _profilePhoto = employee['profile_photo'];

          final payRate = employee['pay_rate'];
          if (payRate != null) {
            _payRateController.text = payRate.toString();
          }

          final commissionRate = employee['commission_rate'];
          if (commissionRate != null) {
            _commissionRateController.text = commissionRate.toString();
          }

          final isActiveValue = employee['is_active'];
          if (isActiveValue == null) {
            _isActive = true;
          } else if (isActiveValue is bool) {
            _isActive = isActiveValue;
          } else if (isActiveValue is int) {
            _isActive = isActiveValue == 1;
          } else if (isActiveValue is String) {
            _isActive = isActiveValue == '1' || isActiveValue.toLowerCase() == 'true';
          } else {
            _isActive = true;
          }

          _isLoading = false;
        });
      } else {
        setState(() {
          _nameController.text = widget.name ?? '';
          _roleController.text = widget.role ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _nameController.text = widget.name ?? '';
        _roleController.text = widget.role ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    try {
      final all = await EmployeeService.getAllEmployees();
      if (all.any((e) => e['staff_id'] != widget.staffId && (e['name'] ?? '').toString().trim().toLowerCase() == name.toLowerCase())) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Another barber named "$name" already exists.'),
            backgroundColor: Colors.orange[800],
          ),
        );
        return;
      }

      if (phone.isNotEmpty && all.any((e) => e['staff_id'] != widget.staffId && (e['phone'] ?? '').toString().trim() == phone)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Phone number "$phone" is already assigned to another barber.'),
            backgroundColor: Colors.orange[800],
          ),
        );
        return;
      }

      if (email.isNotEmpty && all.any((e) => e['staff_id'] != widget.staffId && (e['email'] ?? '').toString().trim().toLowerCase() == email.toLowerCase())) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email "$email" is already in use by another barber.'),
            backgroundColor: Colors.orange[800],
          ),
        );
        return;
      }
    } catch (_) {}

    setState(() {
      _isSaving = true;
    });

    try {
      final updateData = {
        'name': name,
        'phone': phone.isEmpty ? null : phone,
        'email': email.isEmpty ? null : email,
        'role': _roleController.text.trim(),
        'skills': _skillsController.text.trim().isEmpty ? null : _skillsController.text.trim(),
        'pay_rate': _payRateController.text.trim().isEmpty ? null : double.tryParse(_payRateController.text.trim()),
        'commission_rate': _commissionRateController.text.trim().isEmpty ? null : double.tryParse(_commissionRateController.text.trim()),
        'profile_photo': _profilePhoto,
        'is_active': _isActive,
      };

      final result = await EmployeeService.updateEmployee(widget.staffId, updateData);

      if (result['success'] == true && mounted) {
        setState(() {
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Employee updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to update employee'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showDeleteConfirmationDialog() async {
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
              Text(
                'Deactivate / Delete Barber',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to deactivate this barber?\nThey will no longer appear in customer booking schedules.',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
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
                        'Deactivate',
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
      await _deleteEmployee();
    }
  }

  Future<void> _deleteEmployee() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final result = await EmployeeService.deleteEmployee(widget.staffId);

      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Barber deactivated successfully',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? result['error'] ?? 'Failed to deactivate employee',
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
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAvatarWidget() {
    if (_newPhotoBytes != null) {
      return Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF5BBCFF), width: 2)),
        child: ClipOval(child: Image.memory(_newPhotoBytes!, fit: BoxFit.cover)),
      );
    }
    if (_profilePhoto != null && _profilePhoto!.trim().isNotEmpty) {
      String clean = _profilePhoto!.trim();
      if (!clean.startsWith('http://') && !clean.startsWith('https://') && !clean.startsWith('data:image')) {
        if (clean.startsWith('/')) {
          clean = 'http://localhost$clean';
        } else if (clean.startsWith('uploads/')) {
          clean = 'http://localhost/barber_api/$clean';
        }
      }

      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF5BBCFF), width: 2)),
          child: ClipOval(
            child: Image.network(
              clean,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallbackDetailAvatar(),
            ),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF5BBCFF), width: 2)),
          child: ClipOval(child: Image.memory(bytes, fit: BoxFit.cover)),
        );
      } catch (_) {}
    }
    return _buildFallbackDetailAvatar();
  }

  Widget _buildFallbackDetailAvatar() {
    return Container(
      width: 110,
      height: 110,
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
          (_nameController.text.isNotEmpty ? _nameController.text[0] : 'B').toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: 44,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Barber' : 'Barber Details',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context, true),
        ),
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.black87),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _showDeleteConfirmationDialog,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.close, color: Colors.black87),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _loadEmployeeData();
                });
              },
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barber Avatar & Photo Edit
                    Center(
                      child: Stack(
                        children: [
                          _buildAvatarWidget(),
                          if (_isEditing)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _pickImage,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF5BBCFF),
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name
                    TextFormField(
                      controller: _nameController,
                      enabled: _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: GoogleFonts.manrope(),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Please enter name' : null,
                    ),
                    const SizedBox(height: 16),

                    // Role
                    TextFormField(
                      controller: _roleController,
                      enabled: _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Role / Title *',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: GoogleFonts.manrope(),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Please enter role' : null,
                    ),
                    const SizedBox(height: 16),

                    // Phone
                    TextFormField(
                      controller: _phoneController,
                      enabled: _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Phone',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: GoogleFonts.manrope(),
                    ),
                    const SizedBox(height: 16),

                    // Email
                    TextFormField(
                      controller: _emailController,
                      enabled: _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: GoogleFonts.manrope(),
                    ),
                    const SizedBox(height: 16),

                    // Skills
                    TextFormField(
                      controller: _skillsController,
                      enabled: _isEditing,
                      decoration: InputDecoration(
                        labelText: 'Skills & Specialties',
                        prefixIcon: const Icon(Icons.content_cut),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      maxLines: 2,
                      style: GoogleFonts.manrope(),
                    ),
                    const SizedBox(height: 16),

                    // Rates
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _payRateController,
                            enabled: _isEditing,
                            decoration: InputDecoration(
                              labelText: 'Pay Rate (\$)',
                              prefixIcon: const Icon(Icons.attach_money),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.manrope(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _commissionRateController,
                            enabled: _isEditing,
                            decoration: InputDecoration(
                              labelText: 'Commission (0-1.0)',
                              prefixIcon: const Icon(Icons.percent),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.manrope(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Active Switch
                    SwitchListTile(
                      title: Text(
                        'Active Barber',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        _isActive
                            ? 'Barber is active and available for customer bookings'
                            : 'Barber is inactive / hidden from booking schedules',
                        style: GoogleFonts.manrope(fontSize: 12, color: _isActive ? Colors.green : Colors.red),
                      ),
                      value: _isActive,
                      activeColor: const Color(0xFF5BBCFF),
                      onChanged: _isEditing
                          ? (value) => setState(() => _isActive = value)
                          : null,
                    ),

                    if (_isEditing) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveEmployee,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5BBCFF),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'Save Changes',
                                  style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}
