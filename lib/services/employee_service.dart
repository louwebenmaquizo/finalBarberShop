import '../config/api_config.dart';
import 'supabase_service_helpers.dart';

class EmployeeService {
  EmployeeService._();

  static Future<List<Map<String, dynamic>>> getAllEmployees() async {
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.staffDirectoryView)
          .select()
          .order('name');
      final rows = SupabaseServiceHelpers.asMapList(data);
      return Future.wait(rows.map(_normalizeEmployee));
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> searchEmployees(
      String query) async {
    final employees = await getAllEmployees();
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return employees;
    return employees.where((employee) {
      final name = (employee['name'] ?? '').toString().toLowerCase();
      final role = (employee['role'] ?? '').toString().toLowerCase();
      return name.contains(needle) || role.contains(needle);
    }).toList();
  }

  static Future<Map<String, dynamic>?> getEmployeeById(String staffId) async {
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.staffDirectoryView)
          .select()
          .eq('staff_id', staffId)
          .maybeSingle();
      final row = SupabaseServiceHelpers.asMap(data);
      return row.isEmpty ? null : _normalizeEmployee(row);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> createEmployee(
    Map<String, dynamic> employeeData,
  ) async {
    try {
      final email = employeeData['email']?.toString().trim() ?? '';
      final password = employeeData['password']?.toString() ?? '';
      final username = employeeData['username']?.toString().trim() ?? '';
      Map<String, dynamic> staff;

      if (email.isNotEmpty && password.isNotEmpty) {
        final response = await SupabaseConfig.client.functions.invoke(
          'create-staff',
          body: {
            ..._mutationFields(employeeData, includeImage: false),
            'email': email,
            'password': password,
            'username': username.isEmpty ? email.split('@').first : username,
          },
        );
        if (response.status < 200 || response.status >= 300) {
          throw Exception(
            SupabaseServiceHelpers.asMap(response.data)['error'] ??
                'Unable to create the staff login.',
          );
        }
        final payload = SupabaseServiceHelpers.asMap(response.data);
        staff = SupabaseServiceHelpers.asMap(payload['data'] ?? payload);
      } else {
        final data = await SupabaseConfig.client
            .from(SupabaseConfig.staffTable)
            .insert(_mutationFields(employeeData, includeImage: false))
            .select()
            .single();
        staff = SupabaseServiceHelpers.asMap(data);
      }

      final staffId = (staff['staff_id'] ?? staff['id'])?.toString();
      if (staffId == null || staffId.isEmpty) {
        throw Exception('Supabase did not return the new staff ID.');
      }

      final rawPhoto = employeeData['profile_photo'];
      if (SupabaseStorageService.isDataImage(rawPhoto)) {
        final path = await SupabaseStorageService.uploadDataImage(
          bucket: SupabaseConfig.staffAvatarsBucket,
          ownerId: staffId,
          dataUri: rawPhoto.toString(),
        );
        if (path != null) {
          final updated = await SupabaseConfig.client
              .from(SupabaseConfig.staffTable)
              .update({'profile_photo': path})
              .eq('id', staffId)
              .select()
              .single();
          staff = SupabaseServiceHelpers.asMap(updated);
        }
      }

      final normalized = await _normalizeEmployee(staff);
      return {
        'success': true,
        'message': email.isNotEmpty && password.isNotEmpty
            ? 'Staff member and login account created.'
            : 'Staff member created.',
        'data': normalized,
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> updateEmployee(
    String staffId,
    Map<String, dynamic> employeeData,
  ) async {
    try {
      final update = _mutationFields(employeeData, includeImage: false);
      final rawPhoto = employeeData['profile_photo'];
      if (SupabaseStorageService.isDataImage(rawPhoto)) {
        update['profile_photo'] = await SupabaseStorageService.uploadDataImage(
          bucket: SupabaseConfig.staffAvatarsBucket,
          ownerId: staffId,
          dataUri: rawPhoto.toString(),
        );
      } else if (employeeData.containsKey('profile_photo')) {
        final reference = rawPhoto?.toString() ?? '';
        if (!reference.startsWith('http://') &&
            !reference.startsWith('https://')) {
          update['profile_photo'] = reference.isEmpty ? null : reference;
        }
      }

      final data = await SupabaseConfig.client
          .from(SupabaseConfig.staffTable)
          .update(update)
          .eq('id', staffId)
          .select()
          .single();
      return {
        'success': true,
        'message': 'Employee updated successfully',
        'data': await _normalizeEmployee(SupabaseServiceHelpers.asMap(data)),
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> deleteEmployee(String staffId) async {
    try {
      await SupabaseConfig.client
          .from(SupabaseConfig.staffTable)
          .update({'is_active': false}).eq('id', staffId);
      return {
        'success': true,
        'message': 'Employee deactivated successfully',
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Map<String, dynamic> _mutationFields(
    Map<String, dynamic> source, {
    required bool includeImage,
  }) {
    final result = <String, dynamic>{};
    for (final field in const [
      'name',
      'phone',
      'email',
      'role',
      'skills',
      'pay_rate',
      'commission_rate',
      'is_active',
    ]) {
      if (source.containsKey(field)) result[field] = source[field];
    }
    if (includeImage && source.containsKey('profile_photo')) {
      result['profile_photo'] = source['profile_photo'];
    }
    return result;
  }

  static Future<Map<String, dynamic>> _normalizeEmployee(
    Map<String, dynamic> row,
  ) async {
    final employee = Map<String, dynamic>.from(row);
    employee['staff_id'] = employee['staff_id'] ?? employee['id'];
    employee['username'] = employee['username'] ?? '';
    employee['name'] = employee['name'] ?? '';
    employee['role'] = employee['role'] ?? '';
    employee['email'] = employee['email'] ?? '';
    employee['phone'] = employee['phone'] ?? '';
    employee['skills'] = employee['skills'] ?? '';
    employee['is_active'] =
        SupabaseServiceHelpers.asBool(employee['is_active']);
    if (employee['pay_rate'] != null) {
      employee['pay_rate'] =
          SupabaseServiceHelpers.asDouble(employee['pay_rate']);
    }
    if (employee['commission_rate'] != null) {
      employee['commission_rate'] =
          SupabaseServiceHelpers.asDouble(employee['commission_rate']);
    }
    final photo = await SupabaseStorageService.resolveReference(
      bucket: SupabaseConfig.staffAvatarsBucket,
      value: employee['profile_photo'],
      isPublic: true,
    );
    if (photo != null) employee['profile_photo'] = photo;
    return employee;
  }
}
