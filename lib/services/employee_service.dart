import '../config/api_config.dart';
import 'supabase_service_helpers.dart';

class EmployeeService {
  EmployeeService._();

  static List<Map<String, dynamic>>? _cachedEmployees;
  static DateTime? _cacheTime;
  static const Duration _cacheTtl = Duration(minutes: 2);

  static void invalidateCache() {
    _cachedEmployees = null;
    _cacheTime = null;
  }

  static Future<List<Map<String, dynamic>>> getAllEmployees({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedEmployees != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      return _cachedEmployees!;
    }

    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.staffDirectoryView)
          .select()
          .order('name');
      final rows = SupabaseServiceHelpers.asMapList(data);
      final rawList = await Future.wait(rows.map(_normalizeEmployee));

      // Deduplicate employees by staff_id, email, and phone
      final seenIds = <String>{};
      final seenEmails = <String>{};
      final seenPhones = <String>{};
      final uniqueEmployees = <Map<String, dynamic>>[];

      for (final emp in rawList) {
        final id = (emp['staff_id'] ?? emp['id'] ?? '').toString();
        final email = (emp['email'] ?? '').toString().trim().toLowerCase();
        final phone = (emp['phone'] ?? '').toString().trim();

        if (id.isNotEmpty && seenIds.contains(id)) continue;
        if (email.isNotEmpty && seenEmails.contains(email)) continue;
        if (phone.isNotEmpty && seenPhones.contains(phone)) continue;

        if (id.isNotEmpty) seenIds.add(id);
        if (email.isNotEmpty) seenEmails.add(email);
        if (phone.isNotEmpty) seenPhones.add(phone);
        uniqueEmployees.add(emp);
      }

      _cachedEmployees = uniqueEmployees;
      _cacheTime = DateTime.now();

      return uniqueEmployees;
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
    // Check cached employees first
    if (_cachedEmployees != null) {
      for (final e in _cachedEmployees!) {
        if ((e['staff_id'] ?? e['id']) == staffId) return e;
      }
    }

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
      final name = employeeData['name']?.toString().trim() ?? '';
      final email = employeeData['email']?.toString().trim() ?? '';
      final phone = employeeData['phone']?.toString().trim() ?? '';
      final password = employeeData['password']?.toString() ?? '';
      final username = employeeData['username']?.toString().trim() ?? '';

      if (name.isEmpty) {
        return {
          'success': false,
          'message': 'Employee name cannot be empty',
        };
      }

      // Check existing employees for duplicates
      final existingEmployees = await getAllEmployees();

      if (existingEmployees.any((e) =>
          (e['name'] ?? '').toString().trim().toLowerCase() ==
          name.toLowerCase())) {
        return {
          'success': false,
          'message': 'A barber/employee named "$name" already exists.',
        };
      }

      if (phone.isNotEmpty &&
          existingEmployees
              .any((e) => (e['phone'] ?? '').toString().trim() == phone)) {
        return {
          'success': false,
          'message': 'Phone number "$phone" is already assigned to another barber.',
        };
      }

      if (email.isNotEmpty &&
          existingEmployees.any((e) =>
              (e['email'] ?? '').toString().trim().toLowerCase() ==
              email.toLowerCase())) {
        return {
          'success': false,
          'message': 'Email "$email" is already registered to another barber.',
        };
      }

      Map<String, dynamic> staff;

      if (password.isNotEmpty) {
        if (password.length < 8) {
          return {
            'success': false,
            'message': 'Barber login password must be at least 8 characters.',
          };
        }

        final cleanUsername = username.isNotEmpty
            ? username
            : (email.contains('@')
                ? email.split('@').first
                : name.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_'));

        final authEmail = email.contains('@')
            ? email
            : '${cleanUsername.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')}@liembarber.com';

        final response = await SupabaseConfig.client.functions.invoke(
          'create-staff',
          body: {
            ..._mutationFields(employeeData, includeImage: false),
            'name': name,
            'email': authEmail,
            'password': password,
            'username': cleanUsername,
          },
        );
        if (response.status < 200 || response.status >= 300) {
          final payload = SupabaseServiceHelpers.asMap(response.data);
          throw Exception(
            payload['error'] ??
                payload['message'] ??
                'Unable to create the staff login account.',
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

      invalidateCache();

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
      final name = employeeData['name']?.toString().trim();
      final phone = employeeData['phone']?.toString().trim();
      final email = employeeData['email']?.toString().trim();

      // Check duplicates on update
      if (name != null || phone != null || email != null) {
        final existing = await getAllEmployees();
        for (final e in existing) {
          final eId = (e['staff_id'] ?? e['id'] ?? '').toString();
          if (eId == staffId) continue;

          if (name != null &&
              name.isNotEmpty &&
              (e['name'] ?? '').toString().trim().toLowerCase() ==
                  name.toLowerCase()) {
            return {
              'success': false,
              'message': 'Another barber named "$name" already exists.',
            };
          }
          if (phone != null &&
              phone.isNotEmpty &&
              (e['phone'] ?? '').toString().trim() == phone) {
            return {
              'success': false,
              'message': 'Phone number "$phone" is used by another barber.',
            };
          }
          if (email != null &&
              email.isNotEmpty &&
              (e['email'] ?? '').toString().trim().toLowerCase() ==
                  email.toLowerCase()) {
            return {
              'success': false,
              'message': 'Email "$email" is used by another barber.',
            };
          }
        }
      }

      final update = _mutationFields(employeeData, includeImage: false);

      final newPassword = employeeData['password']?.toString().trim();
      if (newPassword != null && newPassword.isNotEmpty) {
        final currentStaff = await getEmployeeById(staffId);
        final existingUserId = currentStaff?['user_id'];
        final staffEmail = (employeeData['email'] ?? currentStaff?['email'] ?? '')
            .toString()
            .trim();
        final staffName = (employeeData['name'] ?? currentStaff?['name'] ?? 'Barber')
            .toString()
            .trim();

        if (existingUserId == null && staffEmail.isNotEmpty) {
          try {
            final cleanUsername = staffEmail.contains('@')
                ? staffEmail.split('@').first
                : staffName
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
            final authEmail = staffEmail.contains('@')
                ? staffEmail
                : '$cleanUsername@liembarber.com';

            final response = await SupabaseConfig.client.functions.invoke(
              'create-staff',
              body: {
                ...update,
                'name': staffName,
                'email': authEmail,
                'password': newPassword,
                'username': cleanUsername,
              },
            );
            if (response.status >= 200 && response.status < 300) {
              final payload = SupabaseServiceHelpers.asMap(response.data);
              final createdStaff =
                  SupabaseServiceHelpers.asMap(payload['data'] ?? payload);
              final createdUserId = createdStaff['user_id'];
              if (createdUserId != null) {
                update['user_id'] = createdUserId;
              }
            }
          } catch (_) {}
        }
      }

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

      invalidateCache();

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
      invalidateCache();
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
