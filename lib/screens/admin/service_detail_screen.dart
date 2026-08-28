import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/catalog_service.dart';

class ServiceDetailScreen extends StatefulWidget {
  final String serviceId;
  final String? name;

  const ServiceDetailScreen({
    super.key,
    required this.serviceId,
    this.name,
  });

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  
  String? _selectedCategoryId;
  bool _isActive = true;
  List<Map<String, dynamic>> _categories = [];
  
  // Image state
  Uint8List? _customImageBytes;
  String? _base64Image;
  String? _existingImageUrl;
  bool _hasDeletedImage = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _priceController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final categories = await CatalogService.getAllCategories();
      final service = await CatalogService.getServiceById(widget.serviceId);

      if (mounted) {
        setState(() {
          _categories = categories;
          
          if (service != null && service.isNotEmpty) {
            _nameController.text = service['name'] ?? '';
            _descriptionController.text = service['description'] ?? '';
            _durationController.text = (service['duration_minutes'] ?? 0).toString();
            
            final priceValue = service['price'];
            if (priceValue != null) {
              _priceController.text = priceValue.toString();
            }
            
            final costValue = service['cost'];
            if (costValue != null) {
              _costController.text = costValue.toString();
            }
            
            _selectedCategoryId = service['category_id'];
            _existingImageUrl = service['image_url'] ?? service['photo'];
            
            final isActiveValue = service['is_active'];
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
          } else {
            _nameController.text = widget.name ?? '';
            _isLoading = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _nameController.text = widget.name ?? '';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final base64Str = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        setState(() {
          _customImageBytes = bytes;
          _base64Image = base64Str;
          _hasDeletedImage = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Service photo selected!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveService() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final serviceName = _nameController.text.trim();

    try {
      final all = await CatalogService.getAllServices();
      if (all.any((s) => s['service_id'] != widget.serviceId && (s['name'] ?? '').toString().trim().toLowerCase() == serviceName.toLowerCase())) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Another service named "$serviceName" already exists in the catalog.'),
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
      final duration = int.tryParse(_durationController.text) ?? 0;
      final price = double.tryParse(_priceController.text) ?? 0.0;
      final cost = _costController.text.isNotEmpty
          ? double.tryParse(_costController.text)
          : null;

      final serviceData = {
        'name': serviceName,
        'category_id': _selectedCategoryId,
        'duration_minutes': duration,
        'price': price,
        'cost': cost,
        'description': _descriptionController.text.trim(),
        'image_url': _hasDeletedImage ? '' : (_base64Image ?? _existingImageUrl),
        'is_active': _isActive,
      };

      final result = await CatalogService.updateService(widget.serviceId, serviceData);

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? result['error'] ?? 'Failed to update service'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving service: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildImageHeader() {
    Widget imageContent;

    if (_hasDeletedImage) {
      imageContent = const Center(
        child: Icon(Icons.add_photo_alternate_outlined, size: 48, color: Color(0xFF1E88E5)),
      );
    } else if (_customImageBytes != null) {
      imageContent = Image.memory(_customImageBytes!, fit: BoxFit.cover);
    } else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
      final clean = _existingImageUrl!.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        imageContent = Image.network(
          clean,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.content_cut, size: 48, color: Colors.grey)),
        );
      } else {
        try {
          final base64Data = clean.contains(',') ? clean.split(',').last : clean;
          final bytes = base64Decode(base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
          imageContent = Image.memory(bytes, fit: BoxFit.cover);
        } catch (_) {
          imageContent = const Center(child: Icon(Icons.content_cut, size: 48, color: Colors.grey));
        }
      }
    } else {
      imageContent = const Center(
        child: Icon(Icons.add_photo_alternate_outlined, size: 48, color: Color(0xFF1E88E5)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Service Image / Photo',
          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _pickImage(ImageSource.gallery),
          child: Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF5BBCFF), width: 1.5),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 180,
                    child: imageContent,
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.photo_library, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'Change',
                              style: GoogleFonts.manrope(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      if (!_hasDeletedImage && (_customImageBytes != null || (_existingImageUrl != null && _existingImageUrl!.isNotEmpty))) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _customImageBytes = null;
                              _base64Image = null;
                              _hasDeletedImage = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.delete_outline, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Edit Service',
          style: GoogleFonts.manrope(
            fontSize: 20,
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
            onPressed: _isSaving ? null : _saveService,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Image Editor Banner
                    _buildImageHeader(),
                    const SizedBox(height: 24),
                    
                    // Service Name
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Service Name *',
                        labelStyle: GoogleFonts.manrope(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: const Icon(Icons.content_cut),
                      ),
                      style: GoogleFonts.manrope(),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter service name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Category Dropdown (Clean, full-width)
                    DropdownButtonFormField<String>(
                      value: _selectedCategoryId,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        labelStyle: GoogleFonts.manrope(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.category_outlined),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      style: GoogleFonts.manrope(color: Colors.black87),
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text('No Category', style: GoogleFonts.manrope(color: Colors.black87)),
                        ),
                        ..._categories.map((category) {
                          return DropdownMenuItem<String>(
                            value: category['category_id'],
                            child: Text(category['name'] ?? '', style: GoogleFonts.manrope(color: Colors.black87)),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 20),

                    // Duration
                    TextFormField(
                      controller: _durationController,
                      decoration: InputDecoration(
                        labelText: 'Duration (minutes) *',
                        labelStyle: GoogleFonts.manrope(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: const Icon(Icons.timer_outlined),
                      ),
                      style: GoogleFonts.manrope(),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter duration';
                        }
                        final duration = int.tryParse(value);
                        if (duration == null || duration <= 0) {
                          return 'Please enter a valid duration';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Price
                    TextFormField(
                      controller: _priceController,
                      decoration: InputDecoration(
                        labelText: 'Price (\$) *',
                        labelStyle: GoogleFonts.manrope(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: const Icon(Icons.attach_money),
                      ),
                      style: GoogleFonts.manrope(),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter price';
                        }
                        final price = double.tryParse(value);
                        if (price == null || price <= 0) {
                          return 'Please enter a valid price';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Cost (optional)
                    TextFormField(
                      controller: _costController,
                      decoration: InputDecoration(
                        labelText: 'Cost (optional)',
                        labelStyle: GoogleFonts.manrope(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: const Icon(Icons.money_off_outlined),
                      ),
                      style: GoogleFonts.manrope(),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 20),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        labelStyle: GoogleFonts.manrope(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: const Icon(Icons.description_outlined),
                      ),
                      style: GoogleFonts.manrope(),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),

                    // Active Switch
                    SwitchListTile(
                      title: Text(
                        'Active Service',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        _isActive
                            ? 'Service is visible and available for customer bookings'
                            : 'Service is hidden from customer booking menu',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: _isActive ? Colors.green : Colors.red,
                        ),
                      ),
                      value: _isActive,
                      activeColor: const Color(0xFF5BBCFF),
                      onChanged: (value) {
                        setState(() {
                          _isActive = value;
                        });
                      },
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveService,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5BBCFF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                'Save Changes',
                                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
