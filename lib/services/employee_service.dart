import '../config/api_config.dart';
import 'api_service.dart' show ApiServiceExtension;

/// Employee Service
/// Contains all functions for employee-related operations
class EmployeeService {
  /// Get all employees for the employee list screen (including inactive)
  static Future<List<Map<String, dynamic>>> getAllEmployees() async {
    try {
      final response = await ApiServiceExtension.get('${ApiConfig.baseUrl}/employees.php?include_inactive=1');
      
      if (response['success'] == true && response['data'] != null) {
        final employees = (response['data'] as List).map((employee) {
          final isActive = employee['is_active'];
          return {
            'staff_id': employee['staff_id'] ?? '',
            'user_id': employee['user_id'] ?? '',
            'username': employee['username'] ?? '',
            'name': employee['name'] ?? '',
            'role': employee['role'] ?? '',
            'email': employee['email'] ?? '',
            'phone': employee['phone'] ?? '',
            'profile_photo': employee['profile_photo'],
            'is_active': isActive,
          };
        }).toList();
        return employees;
      }
      return [];
    } catch (e) {
      print('Error fetching employees: $e');
      return [];
    }
  }
  
  /// Search employees by name or role
  static Future<List<Map<String, dynamic>>> searchEmployees(String query) async {
    final allEmployees = await getAllEmployees();
    if (query.isEmpty) {
      return allEmployees;
    }
    
    final searchQuery = query.toLowerCase();
    return allEmployees.where((employee) {
      final name = (employee['name'] ?? '').toLowerCase();
      final role = (employee['role'] ?? '').toLowerCase();
      return name.contains(searchQuery) || role.contains(searchQuery);
    }).toList();
  }
  
  /// Get employee details by ID
  static Future<Map<String, dynamic>?> getEmployeeById(String staffId) async {
    try {
      final response = await ApiServiceExtension.get('${ApiConfig.baseUrl}/employees.php?staff_id=$staffId');
      
      if (response['success'] == true && response['data'] != null) {
        final employee = response['data'] as Map<String, dynamic>;
        return {
          'staff_id': employee['staff_id'] ?? '',
          'user_id': employee['user_id'] ?? '',
          'username': employee['username'] ?? '',
          'name': employee['name'] ?? '',
          'role': employee['role'] ?? '',
          'email': employee['email'] ?? '',
          'phone': employee['phone'] ?? '',
          'skills': employee['skills'] ?? '',
          'pay_rate': employee['pay_rate'],
          'commission_rate': employee['commission_rate'],
          'profile_photo': employee['profile_photo'],
          'is_active': employee['is_active'] ?? true,
        };
      }
      return null;
    } catch (e) {
      print('Error fetching employee by ID: $e');
      return null;
    }
  }
  
  /// Create new employee
  static Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> employeeData) async {
    try {
      final response = await ApiServiceExtension.post(
        '${ApiConfig.baseUrl}/employees.php',
        employeeData,
      );
      
      return response;
    } catch (e) {
      print('Error creating employee: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
  
  /// Update employee
  static Future<Map<String, dynamic>> updateEmployee(String staffId, Map<String, dynamic> employeeData) async {
    try {
      employeeData['staff_id'] = staffId;
      final response = await ApiServiceExtension.put(
        '${ApiConfig.baseUrl}/employees.php',
        employeeData,
      );
      
      return response;
    } catch (e) {
      print('Error updating employee: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
  
  /// Delete employee (soft delete - sets is_active to FALSE)
  static Future<Map<String, dynamic>> deleteEmployee(String staffId) async {
    try {
      final response = await ApiServiceExtension.delete(
        '${ApiConfig.baseUrl}/employees.php',
        {'staff_id': staffId},
      );
      
      return response;
    } catch (e) {
      print('Error deleting employee: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
