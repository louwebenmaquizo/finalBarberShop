import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/api_config.dart';
import '../../services/auth_session_service.dart';
import '../../services/supabase_service_helpers.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  static const Color primaryBlue = Color(0xFF5BBCFF);

  final _formKey = GlobalKey<FormState>();

  late TextEditingController _fullNameController;
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = true;
  bool _isSaving = false;

  Uint8List? _newImageBytes;
  String? _existingPhoto;
  String? _role = 'admin';

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController();
    _usernameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final session = await AuthSessionService.getSession();
      if (session != null && mounted) {
        setState(() {
          _fullNameController.text =
              session['full_name']?.toString() ?? session['username']?.toString() ?? '';
          _usernameController.text = session['username']?.toString() ?? '';
          _emailController.text = session['email']?.toString() ?? '';
          _phoneController.text = session['phone']?.toString() ?? '';
          _existingPhoto = session['profile_photo']?.toString();
          _role = session['role']?.toString() ?? 'admin';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _newImageBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e', style: GoogleFonts.manrope()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Change Profile Photo',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryBlue.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_library, color: primaryBlue),
                  ),
                  title: Text('Choose from Gallery',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.orange),
                  ),
                  title: Text('Take a Photo',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                if (_newImageBytes != null || _existingPhoto != null)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                    title: Text('Remove Custom Photo',
                        style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w600, color: Colors.red)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _newImageBytes = null;
                        _existingPhoto = null;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final fullName = _fullNameController.text.trim();
    final username = _usernameController.text.trim();
    final phone = _phoneController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.isNotEmpty) {
      if (newPassword.length < 8) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New password must be at least 8 characters',
                style: GoogleFonts.manrope()),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (newPassword != confirmPassword) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Passwords do not match', style: GoogleFonts.manrope()),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final authUser = SupabaseConfig.client.auth.currentUser;
      if (authUser == null) throw Exception('No authenticated user session found.');

      String? photoUrl = _existingPhoto;

      // Handle new photo upload
      if (_newImageBytes != null) {
        final base64String = 'data:image/jpeg;base64,${base64Encode(_newImageBytes!)}';
        try {
          final path = await SupabaseStorageService.uploadDataImage(
            bucket: SupabaseConfig.staffAvatarsBucket,
            ownerId: authUser.id,
            dataUri: base64String,
          );
          if (path != null) {
            photoUrl = await SupabaseStorageService.resolveReference(
              bucket: SupabaseConfig.staffAvatarsBucket,
              value: path,
              isPublic: true,
            );
          }
        } catch (_) {
          photoUrl = base64String;
        }
      }

      // Update Supabase Auth User Metadata & Password
      final userAttributes = UserAttributes(
        password: newPassword.isNotEmpty ? newPassword : null,
        data: {
          'full_name': fullName,
          'username': username,
          'phone': phone,
          if (photoUrl != null) 'avatar_url': photoUrl,
          if (photoUrl != null) 'profile_picture': photoUrl,
          if (photoUrl != null) 'profile_photo': photoUrl,
        },
      );

      await SupabaseConfig.client.auth.updateUser(userAttributes);
      try {
        await SupabaseConfig.client.auth.getUser();
      } catch (_) {}

      // Update public.profiles table username
      try {
        await SupabaseConfig.client
            .from(SupabaseConfig.profilesTable)
            .update({'username': username})
            .eq('id', authUser.id);
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Admin Profile updated successfully!',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
              ],
            ),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e',
                style: GoogleFonts.manrope()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildAvatar() {
    Widget imageWidget;
    if (_newImageBytes != null) {
      imageWidget = Image.memory(_newImageBytes!, fit: BoxFit.cover);
    } else if (_existingPhoto != null && _existingPhoto!.trim().isNotEmpty) {
      final clean = _existingPhoto!.trim();
      if (clean.startsWith('assets/')) {
        imageWidget = Image.asset(clean, fit: BoxFit.cover);
      } else if (clean.startsWith('http://') || clean.startsWith('https://')) {
        imageWidget = Image.network(
          clean,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Image.asset('assets/images/admin_fes.jpg', fit: BoxFit.cover),
        );
      } else {
        try {
          final base64Data = clean.contains(',') ? clean.split(',').last : clean;
          final bytes = base64Decode(
              base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
          imageWidget = Image.memory(bytes, fit: BoxFit.cover);
        } catch (_) {
          imageWidget =
              Image.asset('assets/images/admin_fes.jpg', fit: BoxFit.cover);
        }
      }
    } else {
      imageWidget =
          Image.asset('assets/images/admin_fes.jpg', fit: BoxFit.cover);
    }

    return Center(
      child: Stack(
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: primaryBlue, width: 3),
              boxShadow: [
                BoxShadow(
                  color: primaryBlue.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(child: imageWidget),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _showImagePickerModal,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Admin Profile & Security',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primaryBlue),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Photo
                    _buildAvatar(),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton.icon(
                        onPressed: _showImagePickerModal,
                        icon: const Icon(Icons.edit, size: 16, color: primaryBlue),
                        label: Text(
                          'Change Profile Picture',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: primaryBlue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Personal Information Card
                    _buildSectionHeader('Personal Information', Icons.badge_outlined),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Full Name
                          TextFormField(
                            controller: _fullNameController,
                            validator: (val) =>
                                (val == null || val.trim().isEmpty)
                                    ? 'Full Name is required'
                                    : null,
                            decoration: _buildInputDecoration(
                              label: 'Full Name',
                              icon: Icons.person_outline,
                            ),
                            style: GoogleFonts.manrope(),
                          ),
                          const SizedBox(height: 16),

                          // Username
                          TextFormField(
                            controller: _usernameController,
                            validator: (val) =>
                                (val == null || val.trim().isEmpty)
                                    ? 'Username is required'
                                    : null,
                            decoration: _buildInputDecoration(
                              label: 'Username',
                              icon: Icons.alternate_email,
                            ),
                            style: GoogleFonts.manrope(),
                          ),
                          const SizedBox(height: 16),

                          // Email (Read Only)
                          TextFormField(
                            controller: _emailController,
                            readOnly: true,
                            decoration: _buildInputDecoration(
                              label: 'Email Address (Account ID)',
                              icon: Icons.email_outlined,
                              helperText: 'Primary login identifier',
                            ),
                            style: GoogleFonts.manrope(color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 16),

                          // Phone
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: _buildInputDecoration(
                              label: 'Phone Number',
                              icon: Icons.phone_outlined,
                            ),
                            style: GoogleFonts.manrope(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Password / Security Card
                    _buildSectionHeader('Password & Security', Icons.lock_outline),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Leave password fields blank if you do not wish to change your password.',
                            style: GoogleFonts.manrope(
                              fontSize: 12.5,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // New Password
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: _obscureNewPassword,
                            decoration: _buildInputDecoration(
                              label: 'New Password',
                              icon: Icons.lock_reset,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureNewPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () => setState(() =>
                                    _obscureNewPassword = !_obscureNewPassword),
                              ),
                            ),
                            style: GoogleFonts.manrope(),
                          ),
                          const SizedBox(height: 16),

                          // Confirm New Password
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: _buildInputDecoration(
                              label: 'Confirm New Password',
                              icon: Icons.lock_outline,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () => setState(() =>
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword),
                              ),
                            ),
                            style: GoogleFonts.manrope(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'Save Changes',
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: primaryBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.manrope(color: Colors.grey[600], fontSize: 13.5),
      prefixIcon: Icon(icon, color: primaryBlue, size: 20),
      suffixIcon: suffixIcon,
      helperText: helperText,
      helperStyle: GoogleFonts.manrope(color: Colors.grey[500], fontSize: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
