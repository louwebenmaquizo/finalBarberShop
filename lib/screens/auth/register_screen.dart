import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/countries.dart';
import '../../services/api_service.dart';
import '../../services/employee_service.dart';
import '../../widgets/terms_modal.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Form controllers
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _dateOfBirthController = TextEditingController();

  bool _obscurePassword = true;
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

  // Real system barbers
  List<Map<String, dynamic>> _barbers = [];
  bool _isLoadingBarbers = true;

  @override
  void initState() {
    super.initState();
    _loadBarbers();
  }

  Future<void> _loadBarbers() async {
    try {
      final employees = await EmployeeService.getAllEmployees();
      if (mounted) {
        setState(() {
          // Filter active barbers/staff
          _barbers = employees.where((e) {
            final isActive = e['is_active'];
            bool active = false;
            if (isActive is bool)
              active = isActive;
            else if (isActive is int)
              active = isActive == 1;
            else if (isActive is String)
              active = isActive == '1' || isActive.toLowerCase() == 'true';
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
    _passwordController.dispose();
    _phoneController.dispose();
    _dateOfBirthController.dispose();
    super.dispose();
  }

  void _nextStep() {
    // Validate step 1 (Personal Information) before proceeding
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

  Future<void> _handleRegister() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
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

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Please enter a valid email', style: GoogleFonts.manrope()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password must be at least 8 characters',
              style: GoogleFonts.manrope()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Phone number is required', style: GoogleFonts.manrope()),
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
      // Combine country code with phone number
      final phoneNumber =
          '${_selectedCountry.dialCode}${_phoneController.text.trim()}';

      // Prepare registration data
      final registrationData = {
        'full_name': _fullNameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'phone': phoneNumber,
      };

      // Add optional fields if available
      if (_selectedGender != null && _selectedGender!.isNotEmpty) {
        registrationData['gender'] = _selectedGender!;
      }

      if (_selectedDateOfBirth != null) {
        // Store the date in PostgreSQL's ISO date format.
        registrationData['date_of_birth'] =
            '${_selectedDateOfBirth!.year}-${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}-${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}';
      }

      if (_base64Image != null && _base64Image!.isNotEmpty) {
        registrationData['profile_picture'] = _base64Image!;
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
        registrationData['notes'] = notesParts.join(' | ');
      }

      final result = await ApiService.register(registrationData);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result != null) {
          // Registration successful - customer has been added to schema
          // Show success dialog prompting user to log in
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Registration Successful!',
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'Your account has been created. Check your email to confirm '
                  'the account, then log in with your email and password.',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close dialog
                      // Navigate to login screen
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'Go to Login',
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xB25BBCFF),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        } else {
          // Registration failed
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Registration failed. Please check your information and try again.',
                style: GoogleFonts.manrope(),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Extract error message (remove "Exception: " prefix if present)
        String errorMessage = e.toString();
        if (errorMessage.startsWith('Exception: ')) {
          errorMessage = errorMessage.substring(11);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset:
          false, // Prevent screen from resizing when keyboard opens
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (_currentStep > 0) {
              _previousStep();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Progress indicator with icons
          _buildProgressIndicator(),

          // Page view for steps
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
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
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
              'Personal Information',
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 32),

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
            const SizedBox(height: 24),

            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Email is required';
                }
                if (!value.contains('@') || !value.contains('.')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Email',
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
            const SizedBox(height: 24),

            // Password
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                if (value.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Password',
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
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey[600],
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              style: GoogleFonts.manrope(),
            ),
            const SizedBox(height: 24),

            // Phone Number with Integrated Country Code and Flag Picker
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
            const SizedBox(height: 24),

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
            const SizedBox(height: 24),

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
            const SizedBox(height: 48),

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

  // Step 2: Upload Your Picture
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

          // Choose File Button
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

          // Preferred Barber Dropdown
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
                              decoration: BoxDecoration(
                                color: const Color(0x1A5BBCFF),
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

          // Your Availability Dropdown
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
                      'You are one step away from completing the registration. To wrap this up, you can agree to our ',
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
                  text: '.\n\nWe publish the ',
                ),
                TextSpan(
                  text: 'Company name Terms & Conditions',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const TextSpan(
                  text:
                      ' so that you know what to expect as you use our services.\n\nBy checking the box below, you agree to these terms.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Terms & Conditions Checkbox
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

          // Register Button
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed:
                  (_agreeToTerms && !_isLoading) ? _handleRegister : null,
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
                      'Register',
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
