import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/countries.dart';
import '../../services/api_service.dart';
import '../../services/auth_session_service.dart';
import '../../services/employee_service.dart';
import '../../widgets/terms_modal.dart';
import '../customer/customer_navigation_screen.dart';
import 'login_screen.dart';

class CompleteProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const CompleteProfileScreen({super.key, this.userData});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Form controllers
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _dateOfBirthController = TextEditingController();

  Country _selectedCountry = getDefaultCountry();
  String? _selectedBarber;
  String? _selectedAvailability;
  String? _selectedGender;
  DateTime? _selectedDateOfBirth;
  bool _agreeToTerms = false;
  Uint8List? _selectedImageBytes;
  String? _base64Image;
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _barbers = [];
  bool _isLoadingBarbers = true;

  @override
  void initState() {
    super.initState();
    final data = widget.userData ?? {};
    final existingName = (data['full_name'] ?? data['name'] ?? data['username'] ?? '').toString();
    if (existingName.isNotEmpty && !existingName.contains('@') && existingName.toLowerCase() != 'user') {
      _fullNameController.text = existingName;
    }
    final existingEmail = (data['email'] ?? '').toString();
    if (existingEmail.isNotEmpty) {
      _emailController.text = existingEmail;
    }
    final existingPhone = (data['phone'] ?? '').toString();
    if (existingPhone.isNotEmpty) {
      _phoneController.text = existingPhone;
    }
    _loadBarbers();
  }

  Future<void> _loadBarbers() async {
    try {
      final employees = await EmployeeService.getAllEmployees();
      if (mounted) {
        setState(() {
          _barbers = employees.where((e) {
            final isActive = e['is_active'];
            bool active = false;
            if (isActive is bool) active = isActive;
            else if (isActive is int) active = isActive == 1;
            else if (isActive is String) active = isActive == '1' || isActive.toLowerCase() == 'true';
            return active;
          }).toList();
          _isLoadingBarbers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingBarbers = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dateOfBirthController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_formKey.currentState!.validate()) {
        return;
      }
    }

    if (_currentStep < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep++;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _handleCompleteProfile() async {
    final fullName = _fullNameController.text.trim();
    final phone = _phoneController.text.trim();

    if (fullName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Full name is required', style: GoogleFonts.manrope()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Phone number is required', style: GoogleFonts.manrope()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please agree to Terms & Conditions',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final phoneNumber = '${_selectedCountry.dialCode}${_phoneController.text.trim()}';

      final customerData = <String, dynamic>{
        'full_name': fullName,
        'email': _emailController.text.trim(),
        'phone': phoneNumber,
      };

      if (_selectedGender != null && _selectedGender!.isNotEmpty) {
        customerData['gender'] = _selectedGender!;
      }

      if (_selectedDateOfBirth != null) {
        customerData['date_of_birth'] =
            '${_selectedDateOfBirth!.year}-${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}-${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}';
      }

      if (_base64Image != null && _base64Image!.isNotEmpty) {
        customerData['profile_picture'] = _base64Image!;
      }

      final notesParts = <String>[];
      if (_selectedBarber != null &&
          _selectedBarber!.isNotEmpty &&
          _selectedBarber != 'Any Barber') {
        notesParts.add('Preferred Barber: $_selectedBarber');
      }
      if (_selectedAvailability != null && _selectedAvailability!.isNotEmpty) {
        notesParts.add('Availability: $_selectedAvailability');
      }
      if (notesParts.isNotEmpty) {
        customerData['notes'] = notesParts.join(' | ');
      }

      final result = await ApiService.completeCustomerProfile(customerData);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result['success'] == true) {
          final updatedUser = result['user'] as Map<String, dynamic>? ??
              await AuthSessionService.getSession() ??
              widget.userData;

          if (updatedUser != null) {
            await AuthSessionService.saveSession(updatedUser);
          }

          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    CustomerNavigationScreen(userData: updatedUser),
              ),
              (route) => false,
            );
          }
        } else {
          final errorMsg = result['message'] ?? 'Failed to save profile. Please try again.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg, style: GoogleFonts.manrope()),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error saving profile: $e',
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
          _base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to pick image: $e', style: GoogleFonts.manrope()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Select Profile Photo',
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
                    decoration: const BoxDecoration(
                      color: Color(0x1A5BBCFF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_library,
                        color: Color(0xFF1E88E5)),
                  ),
                  title: Text(
                    'Choose from Gallery',
                    style: GoogleFonts.manrope(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Select a photo from your device storage',
                    style: GoogleFonts.manrope(
                        fontSize: 13, color: Colors.grey[600]),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0x1A5BBCFF),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.camera_alt, color: Color(0xFF1E88E5)),
                  ),
                  title: Text(
                    'Take a Photo',
                    style: GoogleFonts.manrope(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Use your camera to take a new picture',
                    style: GoogleFonts.manrope(
                        fontSize: 13, color: Colors.grey[600]),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                if (_selectedImageBytes != null) ...[
                  const Divider(),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                    title: Text(
                      'Remove Photo',
                      style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedImageBytes = null;
                        _base64Image = null;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (_currentStep > 0) {
              _previousStep();
            } else {
              _confirmSignOut();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: _confirmSignOut,
            child: Text(
              'Sign Out',
              style: GoogleFonts.manrope(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              _buildProgressIndicator(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildPersonalInformationStep(),
                    _buildUploadPictureStep(),
                    _buildPreferenceStep(),
                    _buildTermsStep(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign Out?', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to exit setup and sign out?',
          style: GoogleFonts.manrope(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.manrope()),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthSessionService.clearSession();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Sign Out', style: GoogleFonts.manrope()),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildProgressIcon(0, Icons.person),
          _buildProgressLine(0),
          _buildProgressIcon(1, Icons.camera_alt),
          _buildProgressLine(1),
          _buildProgressIcon(2, Icons.settings),
          _buildProgressLine(2),
          _buildProgressIcon(3, Icons.check_circle),
        ],
      ),
    );
  }

  Widget _buildProgressIcon(int step, IconData icon) {
    final isActive = step <= _currentStep;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? const Color(0xB25BBCFF) : Colors.grey[300],
      ),
      child: Icon(
        icon,
        color: isActive ? Colors.white : Colors.grey[600],
        size: 20,
      ),
    );
  }

  Widget _buildProgressLine(int step) {
    final isActive = step < _currentStep;
    return Expanded(
      child: Container(
        height: 2,
        color: isActive ? const Color(0xB25BBCFF) : Colors.grey[300],
      ),
    );
  }

  // Step 1: Personal Information
  Widget _buildPersonalInformationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Complete Your Profile',
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Please provide a few personal details to set up your customer account.',
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 28),

            // Full Name
            TextFormField(
              controller: _fullNameController,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Full name is required';
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Full Name',
                labelStyle: GoogleFonts.manrope(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              style: GoogleFonts.manrope(),
            ),
            const SizedBox(height: 20),

            // Email (read-only/pre-filled)
            TextFormField(
              controller: _emailController,
              readOnly: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email Address',
                labelStyle: GoogleFonts.manrope(color: Colors.grey[600]),
                suffixIcon: const Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              style: GoogleFonts.manrope(color: Colors.black87),
            ),
            const SizedBox(height: 20),

            // Phone Number with Country Picker
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Phone number is required';
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Phone Number',
                labelStyle: GoogleFonts.manrope(color: Colors.grey[600]),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: InkWell(
                    onTap: () {
                      showCountryPickerModal(
                        context,
                        selectedCountry: _selectedCountry,
                        onSelect: (country) {
                          setState(() {
                            _selectedCountry = country;
                          });
                        },
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedCountry.flag,
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _selectedCountry.dialCode,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.arrow_drop_down,
                          color: Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          height: 24,
                          color: Colors.grey[300],
                        ),
                      ],
                    ),
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
              ),
              style: GoogleFonts.manrope(),
            ),
            const SizedBox(height: 20),

            // Gender Dropdown
            DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: InputDecoration(
                labelText: 'Gender',
                labelStyle: GoogleFonts.manrope(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              items: ['Male', 'Female', 'Other']
                  .map((gender) => DropdownMenuItem(
                        value: gender,
                        child: Text(gender, style: GoogleFonts.manrope()),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedGender = value;
                });
              },
            ),
            const SizedBox(height: 20),

            // Date of Birth
            TextFormField(
              controller: _dateOfBirthController,
              readOnly: true,
              onTap: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.now().subtract(const Duration(days: 365 * 18)),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Color(0xB25BBCFF),
                          onPrimary: Colors.white,
                          onSurface: Colors.black,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  setState(() {
                    _selectedDateOfBirth = picked;
                    _dateOfBirthController.text =
                        '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                  });
                }
              },
              decoration: InputDecoration(
                labelText: 'Date of Birth',
                labelStyle: GoogleFonts.manrope(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                prefixIcon:
                    const Icon(Icons.calendar_today, color: Colors.grey),
              ),
              style: GoogleFonts.manrope(),
            ),
            const SizedBox(height: 36),

            // Next Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xB25BBCFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Next',
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
    );
  }

  // Step 2: Upload Picture
  Widget _buildUploadPictureStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upload Your Picture',
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a profile picture so your barber can recognize you.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 36),

          Center(
            child: GestureDetector(
              onTap: _showImagePickerOptions,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _selectedImageBytes != null
                        ? const Color(0xB25BBCFF)
                        : Colors.grey[300]!,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _selectedImageBytes != null
                    ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.memory(
                              _selectedImageBytes!,
                              width: 220,
                              height: 220,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: Color(0x1A5BBCFF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.photo_library,
                                size: 36, color: Color(0xFF1E88E5)),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Choose from Gallery',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E88E5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to upload or take photo',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_selectedImageBytes != null)
            Center(
              child: TextButton.icon(
                onPressed: _showImagePickerOptions,
                icon: const Icon(Icons.refresh,
                    size: 18, color: Color(0xFF1E88E5)),
                label: Text(
                  'Change Photo',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E88E5),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 36),

          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xB25BBCFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Next',
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
    );
  }

  // Step 3: Preference and Availability
  Widget _buildPreferenceStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preference and Availability',
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 32),

          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: _isLoadingBarbers
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 18),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Loading barbers in system...',
                          style: GoogleFonts.manrope(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : DropdownButtonFormField<String>(
                    value: _selectedBarber,
                    dropdownColor: Colors.white,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
                    style: GoogleFonts.manrope(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Preferred Barber',
                      labelStyle: GoogleFonts.manrope(color: Colors.grey[600]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0x1A5BBCFF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.people_outline,
                                  size: 16, color: Color(0xFF1E88E5)),
                            ),
                            const SizedBox(width: 10),
                            Text('Any Barber (No Preference)',
                                style: GoogleFonts.manrope(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      ..._barbers.map((barber) {
                        final name = barber['name'] ?? 'Barber';
                        final role = barber['role'] ?? 'Barber';
                        final photo = barber['profile_photo'];

                        return DropdownMenuItem<String>(
                          value: name,
                          child: Row(
                            children: [
                              _buildBarberThumbnail(photo, name),
                              const SizedBox(width: 10),
                              Text(name,
                                  style: GoogleFonts.manrope(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  role,
                                  style: GoogleFonts.manrope(
                                      fontSize: 10, color: Colors.grey[700]),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBarber = value;
                      });
                    },
                  ),
          ),
          const SizedBox(height: 24),

          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey),
            ),
            child: DropdownButtonFormField<String>(
              value: _selectedAvailability,
              dropdownColor: Colors.white,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
              style: GoogleFonts.manrope(
                color: Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: 'Your Availability',
                labelStyle: GoogleFonts.manrope(color: Colors.grey[600]),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              items: [
                'Morning (9 AM - 12 PM)',
                'Afternoon (12 PM - 5 PM)',
                'Evening (5 PM - 9 PM)',
                'Flexible'
              ]
                  .map((availability) => DropdownMenuItem(
                        value: availability,
                        child: Text(
                          availability,
                          style: GoogleFonts.manrope(
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedAvailability = value;
                });
              },
            ),
          ),
          const SizedBox(height: 48),

          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xB25BBCFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Next',
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
    );
  }

  // Step 4: Terms and Conditions
  Widget _buildTermsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Almost there',
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),

          RichText(
            text: TextSpan(
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.5,
              ),
              children: [
                const TextSpan(
                  text:
                      'You are one step away from completing your account setup. To wrap this up, please review and agree to our ',
                ),
                TextSpan(
                  text: 'Terms & Conditions',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const TextSpan(
                  text: '.\n\nBy checking the box below, you agree to these terms.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _agreeToTerms,
                  onChanged: (value) {
                    setState(() {
                      _agreeToTerms = value ?? false;
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  activeColor: const Color(0xB25BBCFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    showTermsAndConditionsModal(context);
                  },
                  child: Text(
                    'Terms & Conditions (tap to read)',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E88E5),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),

          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed:
                  (_agreeToTerms && !_isLoading) ? _handleCompleteProfile : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xB25BBCFF),
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Complete & Get Started',
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
    );
  }

  Widget _buildBarberThumbnail(String? photo, String name) {
    if (photo != null && photo.isNotEmpty) {
      final clean = photo.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            clean,
            width: 24,
            height: 24,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackInitial(name),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(
            base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            bytes,
            width: 24,
            height: 24,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackInitial(name),
          ),
        );
      } catch (_) {}
    }
    return _buildFallbackInitial(name);
  }

  Widget _buildFallbackInitial(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'B';
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        color: Color(0xFF5BBCFF),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
            fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}
