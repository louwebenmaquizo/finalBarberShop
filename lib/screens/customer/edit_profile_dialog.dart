import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/auth_session_service.dart';

void showEditProfileDialog(
  BuildContext context, {
  required Map<String, dynamic>? userData,
  required ValueChanged<Map<String, dynamic>> onUpdated,
}) {
  showDialog(
    context: context,
    builder: (context) => _EditProfileDialogContent(
      userData: userData,
      onUpdated: onUpdated,
    ),
  );
}

class _EditProfileDialogContent extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final ValueChanged<Map<String, dynamic>> onUpdated;

  const _EditProfileDialogContent({
    required this.userData,
    required this.onUpdated,
  });

  @override
  State<_EditProfileDialogContent> createState() =>
      _EditProfileDialogContentState();
}

class _EditProfileDialogContentState extends State<_EditProfileDialogContent> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  String? _gender;
  bool _isLoading = false;

  Uint8List? _newImageBytes;
  String? _base64Image;
  String? _existingPhoto;
  bool _hasChangedPhoto = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.userData?['full_name'] ?? widget.userData?['username'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.userData?['phone'] ?? '',
    );
    _emailController = TextEditingController(
      text: widget.userData?['email'] ?? '',
    );
    _gender = widget.userData?['gender'] ?? 'Male';
    _existingPhoto = widget.userData?['profile_picture'] ??
        widget.userData?['profile_photo'];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
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
          _base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          _hasChangedPhoto = true;
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

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Name is required', style: GoogleFonts.manrope()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final customerId = widget.userData?['customer_id'] ?? '';
      final userId = widget.userData?['user_id'] ?? '';

      final Map<String, dynamic> payload = {
        'customer_id': customerId,
        'user_id': userId,
        'full_name': name,
        'phone': phone,
        'gender': _gender,
      };

      if (_hasChangedPhoto) {
        payload['profile_picture'] = _base64Image ?? '';
      }

      final response = await ApiService.updateCustomerProfile(
        customerId.toString(),
        payload,
      );

      if (response != null && mounted) {
        final updatedData = Map<String, dynamic>.from(widget.userData ?? {});
        updatedData['full_name'] = name;
        updatedData['phone'] = phone;
        updatedData['gender'] = _gender;
        if (_hasChangedPhoto) {
          final serverPhoto = response['profile_picture'];
          updatedData['profile_picture'] = serverPhoto ?? _base64Image;
          updatedData['profile_photo'] = updatedData['profile_picture'];
        }
        await AuthSessionService.saveSession(updatedData);
        widget.onUpdated(updatedData);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile updated successfully!',
                style: GoogleFonts.manrope()),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to update profile'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error updating profile: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildAvatarPreview() {
    if (_newImageBytes != null) {
      return ClipOval(
        child: Image.memory(
          _newImageBytes!,
          width: 90,
          height: 90,
          fit: BoxFit.cover,
        ),
      );
    }

    if (_existingPhoto != null &&
        _existingPhoto!.trim().isNotEmpty &&
        !_hasChangedPhoto) {
      String clean = _existingPhoto!.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return ClipOval(
          child: Image.network(
            clean,
            width: 90,
            height: 90,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackAvatar(),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(
            base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return ClipOval(
          child: Image.memory(bytes, width: 90, height: 90, fit: BoxFit.cover),
        );
      } catch (_) {}
    }

    return _buildFallbackAvatar();
  }

  Widget _buildFallbackAvatar() {
    final name = _nameController.text.trim();
    final initial = (name.isNotEmpty ? name[0] : 'C').toUpperCase();
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.manrope(
          fontSize: 36,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF1E88E5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit Profile',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Profile Photo Section
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => _pickImage(ImageSource.gallery),
                      child: Stack(
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0x1A5BBCFF),
                              border: Border.all(
                                  color: const Color(0xFF5BBCFF), width: 2),
                            ),
                            child: _buildAvatarPreview(),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF5BBCFF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library,
                              size: 14, color: Color(0xFF1E88E5)),
                          label: Text(
                            (_newImageBytes != null ||
                                    (_existingPhoto != null &&
                                        _existingPhoto!.isNotEmpty &&
                                        !_hasChangedPhoto))
                                ? 'Change Photo'
                                : 'Upload Photo',
                            style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E88E5)),
                          ),
                        ),
                        if (_newImageBytes != null ||
                            (_existingPhoto != null &&
                                _existingPhoto!.isNotEmpty &&
                                !_hasChangedPhoto)) ...[
                          const SizedBox(width: 4),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _newImageBytes = null;
                                _base64Image = null;
                                _existingPhoto = null;
                                _hasChangedPhoto = true;
                              });
                            },
                            icon: const Icon(Icons.delete_outline,
                                size: 14, color: Colors.red),
                            label: Text('Remove',
                                style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Full Name
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon:
                      const Icon(Icons.person_outline, color: Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                style: GoogleFonts.manrope(),
              ),
              const SizedBox(height: 16),

              // Email (Read only)
              TextField(
                controller: _emailController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon:
                      const Icon(Icons.email_outlined, color: Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                style: GoogleFonts.manrope(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),

              // Phone
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon:
                      const Icon(Icons.phone_outlined, color: Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                style: GoogleFonts.manrope(),
              ),
              const SizedBox(height: 16),

              // Gender
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: InputDecoration(
                  labelText: 'Gender',
                  prefixIcon: const Icon(Icons.transgender, color: Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                items: ['Male', 'Female', 'Other']
                    .map((g) => DropdownMenuItem(
                        value: g, child: Text(g, style: GoogleFonts.manrope())))
                    .toList(),
                onChanged: (val) => setState(() => _gender = val),
              ),
              const SizedBox(height: 24),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5BBCFF),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(
                          'Save Changes',
                          style: GoogleFonts.manrope(
                              fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
