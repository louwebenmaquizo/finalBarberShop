import '../config/api_config.dart';
import 'api_service.dart' show ApiServiceExtension;

/// Catalog Service
/// Contains all functions for catalog/service-related operations
/// One function per screen/feature
class CatalogService {
  // Catalog Screen Functions
  
  /// Get all services for the catalog screen (including inactive)
  /// Returns a list of services with name, description, price, etc.
  static Future<List<Map<String, dynamic>>> getAllServices() async {
    try {
      // Include inactive services by adding include_inactive parameter
      final response = await ApiServiceExtension.get('${ApiConfig.baseUrl}/services.php?include_inactive=1');
      
      if (response['success'] == true && response['data'] != null) {
        final services = (response['data'] as List).map((service) {
          // Convert price to double safely (handle int, double, or String)
          dynamic priceValue = service['price'];
          double? price;
          if (priceValue is int) {
            price = priceValue.toDouble();
          } else if (priceValue is double) {
            price = priceValue;
          } else if (priceValue is String) {
            price = double.tryParse(priceValue);
          } else if (priceValue is num) {
            price = priceValue.toDouble();
          }
          
          // Convert cost to double safely
          dynamic costValue = service['cost'];
          double? cost;
          if (costValue is int) {
            cost = costValue.toDouble();
          } else if (costValue is double) {
            cost = costValue;
          } else if (costValue is String) {
            cost = double.tryParse(costValue);
          } else if (costValue is num) {
            cost = costValue.toDouble();
          }
          
          // Preserve the original is_active value from schema (1 = active, 0 = inactive)
          // Keep as integer to match schema exactly
          dynamic isActiveValue = service['is_active'];
          int isActiveInt;
          if (isActiveValue == null) {
            isActiveInt = 1; // Default to active (1) if null
          } else if (isActiveValue is bool) {
            isActiveInt = isActiveValue ? 1 : 0;
          } else if (isActiveValue is int) {
            isActiveInt = isActiveValue; // Keep as-is (1 or 0)
          } else if (isActiveValue is String) {
            final lower = isActiveValue.toLowerCase().trim();
            isActiveInt = (lower == 'true' || lower == '1' || lower == 'yes') ? 1 : 0;
          } else {
            isActiveInt = 1; // Default fallback to active
          }
          
          return {
            'service_id': service['service_id'] ?? '',
            'name': service['name'] ?? '',
            'category_id': service['category_id'],
            'category_name': service['category_name'],
            'duration_minutes': service['duration_minutes'] ?? 0,
            'price': price ?? 0.0,
            'cost': cost,
            'description': service['description'] ?? '',
            'image_url': service['image_url'] ?? service['photo'],
            'is_active': isActiveInt, // Keep as integer (1 or 0) to match schema
          };
        }).toList();
        return services;
      }
      return [];
    } catch (e) {
      print('Error fetching services: $e');
      return [];
    }
  }
  
  /// Search services by name or description
  /// Used for filtering in the catalog screen
  static Future<List<Map<String, dynamic>>> searchServices(String query) async {
    final allServices = await getAllServices();
    if (query.isEmpty) {
      return allServices;
    }
    
    final searchQuery = query.toLowerCase();
    return allServices.where((service) {
      final name = (service['name'] ?? '').toLowerCase();
      final description = (service['description'] ?? '').toLowerCase();
      final category = (service['category_name'] ?? '').toLowerCase();
      return name.contains(searchQuery) || 
             description.contains(searchQuery) || 
             category.contains(searchQuery);
    }).toList();
  }
  
  /// Get service details by ID
  /// For service detail screen (future implementation)
  static Future<Map<String, dynamic>?> getServiceById(String serviceId) async {
    try {
      final response = await ApiServiceExtension.get('${ApiConfig.baseUrl}/services.php?service_id=$serviceId');
      
      if (response['success'] == true && response['data'] != null) {
        final service = response['data'] as Map<String, dynamic>;
        
        // Convert price to double safely (handle int, double, or String)
        dynamic priceValue = service['price'];
        double? price;
        if (priceValue is int) {
          price = priceValue.toDouble();
        } else if (priceValue is double) {
          price = priceValue;
        } else if (priceValue is String) {
          price = double.tryParse(priceValue);
        } else if (priceValue is num) {
          price = priceValue.toDouble();
        }
        
        // Convert cost to double safely
        dynamic costValue = service['cost'];
        double? cost;
        if (costValue is int) {
          cost = costValue.toDouble();
        } else if (costValue is double) {
          cost = costValue;
        } else if (costValue is String) {
          cost = double.tryParse(costValue);
        } else if (costValue is num) {
          cost = costValue.toDouble();
        }
        
        return {
          'service_id': service['service_id'] ?? '',
          'name': service['name'] ?? '',
          'category_id': service['category_id'],
          'category_name': service['category_name'],
          'duration_minutes': service['duration_minutes'] ?? 0,
          'price': price ?? 0.0,
          'cost': cost,
          'description': service['description'] ?? '',
          'image_url': service['image_url'] ?? service['photo'],
          'is_active': service['is_active'] ?? true,
        };
      }
      return null;
    } catch (e) {
      print('Error fetching service by ID: $e');
      return null;
    }
  }
  
  /// Create new service
  /// For add service functionality (future implementation)
  static Future<Map<String, dynamic>> createService(Map<String, dynamic> serviceData) async {
    try {
      final response = await ApiServiceExtension.post(
        '${ApiConfig.baseUrl}/services.php',
        serviceData,
      );
      
      return response;
    } catch (e) {
      print('Error creating service: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
  
  /// Update service
  /// For edit service functionality (future implementation)
  static Future<Map<String, dynamic>> updateService(String serviceId, Map<String, dynamic> serviceData) async {
    try {
      serviceData['service_id'] = serviceId;
      final response = await ApiServiceExtension.put(
        '${ApiConfig.baseUrl}/services.php',
        serviceData,
      );
      
      return response;
    } catch (e) {
      print('Error updating service: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
  
  /// Delete service (soft delete - sets is_active to FALSE)
  /// For delete service functionality (future implementation)
  static Future<Map<String, dynamic>> deleteService(String serviceId) async {
    try {
      final response = await ApiServiceExtension.delete(
        '${ApiConfig.baseUrl}/services.php',
        {'service_id': serviceId},
      );
      
      return response;
    } catch (e) {
      print('Error deleting service: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
  
  /// Get all service categories
  /// Used for category dropdown and filtering
  static Future<List<Map<String, dynamic>>> getAllCategories() async {
    try {
      final response = await ApiServiceExtension.get(ApiConfig.categoriesUrl);
      
      if (response['success'] == true && response['data'] != null) {
        final categories = (response['data'] as List).map((category) {
          return {
            'category_id': category['category_id'] ?? '',
            'name': category['name'] ?? '',
            'description': category['description'],
            'service_count': category['service_count'] ?? 0,
          };
        }).toList();
        return categories;
      }
      return [];
    } catch (e) {
      print('Error fetching categories: $e');
      return [];
    }
  }

  /// Create a new service category
  static Future<Map<String, dynamic>> createCategory(String name, String? description) async {
    try {
      final response = await ApiServiceExtension.post(
        ApiConfig.categoriesUrl,
        {
          'name': name,
          'description': description,
        },
      );
      return response;
    } catch (e) {
      print('Error creating category: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Update existing service category
  static Future<Map<String, dynamic>> updateCategory(String categoryId, String name, String? description) async {
    try {
      final response = await ApiServiceExtension.put(
        ApiConfig.categoriesUrl,
        {
          'category_id': categoryId,
          'name': name,
          'description': description,
        },
      );
      return response;
    } catch (e) {
      print('Error updating category: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Delete a service category
  static Future<Map<String, dynamic>> deleteCategory(String categoryId) async {
    try {
      final response = await ApiServiceExtension.delete(
        ApiConfig.categoriesUrl,
        {'category_id': categoryId},
      );
      return response;
    } catch (e) {
      print('Error deleting category: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}

