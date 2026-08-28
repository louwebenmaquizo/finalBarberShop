import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiService {
  // Login
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      print('🔐 Attempting login for: $username');
      print('🌐 API URL: ${ApiConfig.loginUrl}');
      
      final response = await http.post(
        Uri.parse(ApiConfig.loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      print('📡 Response status: ${response.statusCode}');
      print('📦 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Parsed response: $data');
        
        if (data['success'] == true && data['data'] != null) {
          return {
            'success': true,
            'user': data['data'],
          };
        } else {
          // Return error message from API
          return {
            'success': false,
            'message': data['error'] ?? 'Invalid username or password',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ Login error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Register
  static Future<Map<String, dynamic>?> register(Map<String, dynamic> userData) async {
    try {
      print('📝 Attempting registration for: ${userData['email']}');
      print('🌐 API URL: ${ApiConfig.registerUrl}');
      print('📤 Request data: ${jsonEncode(userData)}');
      
      final response = await http.post(
        Uri.parse(ApiConfig.registerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(userData),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout - server may be unreachable. Check your API URL and ensure the server is running.');
        },
      );

      print('📡 Response status: ${response.statusCode}');
      print('📦 Response body: ${response.body}');

      // Try to parse response body
      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid server response: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      }
      
      print('✅ Parsed response: $data');
      
      if (response.statusCode == 200 && data['success'] == true) {
        return data['data'];
      } else {
        // Extract error message from response
        final errorMessage = data['error'] ?? data['message'] ?? 'Registration failed';
        print('❌ Registration failed: $errorMessage');
        throw Exception(errorMessage);
      }
    } on http.ClientException catch (e) {
      print('❌ Network error: $e');
      throw Exception('Network error: Unable to connect to server. Please check:\n1. Server is running\n2. API URL is correct\n3. Network connection is active');
    } catch (e) {
      print('❌ Register error: $e');
      rethrow; // Re-throw to let the UI handle the error
    }
  }

  // Get all customers
  static Future<List<dynamic>> getCustomers() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.customersUrl));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'] as List;
        }
      }
      return [];
    } catch (e) {
      print('Get customers error: $e');
      return [];
    }
  }

  // Get all appointments (optionally filtered by customer_id and upcoming only)
  static Future<List<dynamic>> getAppointments({String? customerId, bool upcomingOnly = false}) async {
    try {
      String url = ApiConfig.appointmentsUrl;
      List<String> params = [];
      
      if (customerId != null && customerId.isNotEmpty) {
        params.add('customer_id=$customerId');
      }
      
      if (upcomingOnly) {
        params.add('upcoming_only=1');
      }
      
      if (params.isNotEmpty) {
        url += '?${params.join('&')}';
      }
      
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'] as List;
        }
      }
      return [];
    } catch (e) {
      print('Get appointments error: $e');
      return [];
    }
  }
  

  // Create appointment
  static Future<Map<String, dynamic>?> createAppointment(Map<String, dynamic> appointmentData) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.appointmentsUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(appointmentData),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
      return null;
    } catch (e) {
      print('Create appointment error: $e');
      return null;
    }
  }

  // Get customer's own appointments
  static Future<List<dynamic>> getCustomerAppointments(String customerId) async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.customerAppointments(customerId)),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'] as List;
        }
      }
      return [];
    } catch (e) {
      print('Get customer appointments error: $e');
      return [];
    }
  }

  // Get customer profile
  static Future<Map<String, dynamic>?> getCustomerProfile(String customerId) async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.customerProfile(customerId)),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
      return null;
    } catch (e) {
      print('Get customer profile error: $e');
      return null;
    }
  }

  // Update customer profile
  static Future<Map<String, dynamic>?> updateCustomerProfile(
    String customerId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      final response = await http.put(
        Uri.parse(ApiConfig.customerProfile(customerId)),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(profileData),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
      return null;
    } catch (e) {
      print('Update customer profile error: $e');
      return null;
    }
  }

  // Check if feedback exists for an appointment
  static Future<bool> hasFeedback(String appointmentId, String customerId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.feedbackUrl}?appointment_id=$appointmentId&customer_id=$customerId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Check has_feedback flag or if data exists
          return data['has_feedback'] == true || data['data'] != null;
        }
      }
      return false;
    } catch (e) {
      print('Error checking feedback: $e');
      return false;
    }
  }

  // Submit feedback/rating
  static Future<Map<String, dynamic>> submitFeedback({
    required String appointmentId,
    required String customerId,
    required int rating,
    String? comments,
  }) async {
    try {
      print('📝 Submitting feedback for appointment: $appointmentId');
      print('🌐 API URL: ${ApiConfig.feedbackUrl}');
      
      final response = await http.post(
        Uri.parse(ApiConfig.feedbackUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'appointment_id': appointmentId,
          'customer_id': customerId,
          'rating': rating,
          'comments': comments ?? '',
        }),
      );

      print('📡 Response status: ${response.statusCode}');
      print('📦 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return {
            'success': true,
            'message': data['message'] ?? 'Feedback submitted successfully',
          };
        } else {
          return {
            'success': false,
            'message': data['error'] ?? data['message'] ?? 'Failed to submit feedback',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ Submit feedback error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }
}

/// Extended API Service with generic HTTP methods
/// Used by service files for specific operations
class ApiServiceExtension {
  static Future<Map<String, dynamic>> get(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'success': false, 'message': 'Server error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  static Future<Map<String, dynamic>> post(String url, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      
      print('📡 POST Response status: ${response.statusCode}');
      print('📦 POST Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        try {
          // Check if response is valid JSON
          final decoded = jsonDecode(response.body);
          return decoded;
        } catch (jsonError) {
          print('❌ JSON decode error: $jsonError');
          print('Response body (first 500 chars): ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
          return {
            'success': false,
            'message': 'Invalid JSON response from server. The server may have returned an error page.',
            'error': jsonError.toString(),
            'response_preview': response.body.length > 200 
                ? response.body.substring(0, 200) 
                : response.body
          };
        }
      }
      return {'success': false, 'message': 'Server error: ${response.statusCode}'};
    } catch (e) {
      print('❌ POST request error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }
  
  static Future<Map<String, dynamic>> put(String url, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'success': false, 'message': 'Server error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  static Future<Map<String, dynamic>> delete(String url, Map<String, dynamic>? data) async {
    try {
      final uri = Uri.parse(url);
      final request = http.Request('DELETE', uri);
      if (data != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(data);
      }
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        return jsonDecode(responseBody);
      }
      return {'success': false, 'message': 'Server error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}


