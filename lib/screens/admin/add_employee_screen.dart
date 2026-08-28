import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/employee_service.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key});

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _roleController =
      TextEditingController(text: 'Master Barber');
  final TextEditingController _skillsController = TextEditingController();
  final TextEditingController _payRateController = TextEditingController();
  final TextEditingController _commissionRateController =
      TextEditingController();

  // Barber Account Credentials
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Profile Picture State
  Uint8List? _imageBytes;
  String? _base64Image;
  bool _isActive = true;
  List<Map<String, dynamic>> _existingEmployees = [];

  @override
  void initState() {
    super.initState();
    _loadExistingEmployees();
  }

  Future<void> _loadExistingEmployees() async {
    try {
      final list = await EmployeeService.getAllEmployees();
      if (mounted) {
        setState(() {
          _existingEmployees = list;
        });
      }
    } catch (_) {}
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
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final base64Str = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        setState(() {
          _imageBytes = bytes;
          _base64Image = base64Str;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error selecting image: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();

    // Client-side Duplicate Checks
    if (_existingEmployees.any((e) =>
        (e['name'] ?? '').toString().trim().toLowerCase() ==
        name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A barber/employee named "$name" already exists.'),
          backgroundColor: Colors.orange[800],
        ),
      );
      return;
    }

    if (phone.isNotEmpty &&
        _existingEmployees
            .any((e) => (e['phone'] ?? '').toString().trim() == phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Phone number "$phone" is already assigned to another barber.'),
          backgroundColor: Colors.orange[800],
        ),
      );
      return;
    }

    if (email.isNotEmpty &&
        _existingEmployees.any((e) =>
            (e['email'] ?? '').toString().trim().toLowerCase() ==
            email.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Email "$email" is already registered to another barber.'),
          backgroundColor: Colors.orange[800],
        ),
      );
      return;
    }

    if (username.isNotEmpty &&
        _existingEmployees.any((e) =>
            (e['username'] ?? '').toString().trim().toLowerCase() ==
            username.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Username "$username" is already in use.'),
          backgroundColor: Colors.orange[800],
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final employeeData = {
        'name': name,
        'phone': phone.isEmpty ? null : phone,
        'email': email.isEmpty ? null : email,
        'role': _roleController.text.trim(),
        'skills': _skillsController.text.trim().isEmpty
            ? null
            : _skillsController.text.trim(),
        'pay_rate': _payRateController.text.trim().isEmpty
            ? null
            : double.tryParse(_payRateController.text.trim()),
        'commission_rate': _commissionRateController.text.trim().isEmpty
            ? null
            : double.tryParse(_commissionRateController.text.trim()),
        'profile_photo': _base64Image,
        'username': username.isEmpty ? null : username,
        'password': _passwordController.text.trim().isEmpty
            ? null
            : _passwordController.text.trim(),
        'is_active': _isActive,
      };

      final result = await EmployeeService.createEmployee(employeeData);

      if (result['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message']?.toString() ?? 'Barber added successfully',
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to add employee'),
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

  Widget _buildPhotoUploader() {
    return Center(
      child: Column(
        children: [
          // Clickable Circle Avatar
          GestureDetector(
            onTap: () => _pickImage(ImageSource.gallery),
            child: Stack(
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x1A5BBCFF),
                    border: Border.all(
                      color: _imageBytes != null
                          ? Colors.green
                          : const Color(0xFF5BBCFF),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5BBCFF).withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _imageBytes != null
                        ? Image.memory(
                            _imageBytes!,
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.add_a_photo_outlined,
                                size: 36,
                                color: Color(0xFF1E88E5),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap to Add',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1E88E5),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _imageBytes != null
                          ? Colors.green
                          : const Color(0xFF5BBCFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(
                      _imageBytes != null ? Icons.check : Icons.camera_alt,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Upload / Change Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library,
                    size: 16, color: Colors.white),
                label: Text(
                  _imageBytes != null ? 'Change Photo' : 'Upload from Gallery',
                  style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5BBCFF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
              if (_imageBytes != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _imageBytes = null;
                      _base64Image = null;
                    });
                  },
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Colors.red),
                  label: Text(
                    'Remove',
                    style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: Colors.red,
                        fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Add Barber / Staff',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveEmployee,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E88E5),
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo Uploader
              _buildPhotoUploader(),
              const SizedBox(height: 24),

              // Basic Info Section
              Text('Barber Information',
                  style: GoogleFonts.manrope(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name *',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                style: GoogleFonts.manrope(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter barber name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Role / Position Field
              TextFormField(
                controller: _roleController,
                decoration: InputDecoration(
                  labelText: 'Role / Position *',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  hintText: 'e.g. Master Barber, Senior Stylist',
                ),
                style: GoogleFonts.manrope(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter role';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone Field
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.phone,
                style: GoogleFonts.manrope(),
              ),
              const SizedBox(height: 16),

              // Email Field
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.manrope(),
              ),
              const SizedBox(height: 16),

              // Skills & Specialties Field
              TextFormField(
                controller: _skillsController,
                decoration: InputDecoration(
                  labelText: 'Skills & Specialties',
                  prefixIcon: const Icon(Icons.content_cut),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  hintText: 'e.g. Fade, Beard Trim, Hot Towel Shave',
                ),
                maxLines: 2,
                style: GoogleFonts.manrope(),
              ),
              const SizedBox(height: 16),

              // Rates Section
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _payRateController,
                      decoration: InputDecoration(
                        labelText: 'Hourly Pay (\$)',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.manrope(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _commissionRateController,
                      decoration: InputDecoration(
                        labelText: 'Commission (0-1.0)',
                        prefixIcon: const Icon(Icons.percent),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.manrope(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Barber Portal Login Credentials Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x0D5BBCFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x335BBCFF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_circle,
                            color: Color(0xFF1E88E5), size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Barber Portal Login Account',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E88E5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create login credentials so this barber can log in and view their daily customer appointments.',
                      style: GoogleFonts.manrope(
                          fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),

                    // Username Field
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Barber Username',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'e.g. marcus_barber',
                      ),
                      style: GoogleFonts.manrope(),
                    ),
                    const SizedBox(height: 14),

                    // Password Field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Barber Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'e.g. barber123',
                      ),
                      style: GoogleFonts.manrope(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Active Switch
              SwitchListTile(
                title: Text(
                  'Active Status',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _isActive
                      ? 'Barber is active and available for customer bookings'
                      : 'Barber is inactive',
                  style: GoogleFonts.manrope(
                      fontSize: 12, color: Colors.grey[600]),
                ),
                value: _isActive,
                activeColor: const Color(0xFF5BBCFF),
                onChanged: (value) => setState(() => _isActive = value),
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveEmployee,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5BBCFF),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'Add Barber & Create Account',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
