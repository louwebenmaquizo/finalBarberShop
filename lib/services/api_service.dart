import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/api_config.dart';
import 'auth_session_service.dart';
import 'supabase_service_helpers.dart';

/// Compatibility facade used by the existing screens.
///
/// All operations go directly through the Supabase SDK. The methods preserve
/// the old PHP response shapes so the UI can be migrated independently.
class ApiService {
  ApiService._();

  static Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      // Use the app's current origin so OAuth redirect works regardless of port
      String? redirectTo;
      if (kIsWeb) {
        try {
          final uri = Uri.base;
          redirectTo = '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
        } catch (_) {
          redirectTo = 'http://localhost:5000';
        }
      }
      await SupabaseConfig.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        scopes: 'email profile',
      );
      return {'success': true};
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> completeCustomerProfile(
    Map<String, dynamic> customerData,
  ) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      return {'success': false, 'message': 'No authenticated user found.'};
    }

    final fullName = (customerData['full_name'] ?? '').toString().trim();
    final phone = (customerData['phone'] ?? '').toString().trim();
    if (fullName.isEmpty || phone.isEmpty) {
      return {
        'success': false,
        'message': 'Full name and phone number are required.',
      };
    }

    try {
      final username = (customerData['username'] ??
              user.userMetadata?['username'] ??
              (user.email != null && user.email!.contains('@')
                  ? user.email!.split('@').first
                  : 'User'))
          .toString()
          .trim();

      // 1. Upsert profile if allowed by RLS (otherwise handled by DB trigger)
      try {
        await SupabaseConfig.client.from(SupabaseConfig.profilesTable).upsert({
          'id': user.id,
          'username': username,
          'role': 'customer',
          'is_active': true,
        });
      } catch (_) {
        // Ignored: profiles table may be managed via trigger or restricted by RLS
      }

      // 2. Check if customer record exists
      final existing = await SupabaseConfig.client
          .from(SupabaseConfig.customersTable)
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      String? customerId = existing != null ? existing['id']?.toString() : null;

      // 3. Handle profile picture upload if needed
      String? profilePicturePath;
      final rawPicture = customerData['profile_picture'];
      if (rawPicture != null && SupabaseStorageService.isDataImage(rawPicture)) {
        try {
          profilePicturePath = await SupabaseStorageService.uploadDataImage(
            bucket: SupabaseConfig.customerAvatarsBucket,
            ownerId: customerId ?? user.id,
            dataUri: rawPicture.toString(),
          );
        } catch (_) {}
      }

      final customerPayload = <String, dynamic>{
        'user_id': user.id,
        'full_name': fullName,
        'phone': phone,
        'email': user.email ?? customerData['email'],
        if (customerData['gender'] != null) 'gender': customerData['gender'],
        if (customerData['date_of_birth'] != null)
          'date_of_birth': customerData['date_of_birth'],
        if (customerData['notes'] != null) 'notes': customerData['notes'],
        if (profilePicturePath != null) 'profile_picture': profilePicturePath,
      };

      Map<String, dynamic> savedCustomer;
      if (customerId != null) {
        final res = await SupabaseConfig.client
            .from(SupabaseConfig.customersTable)
            .update(customerPayload)
            .eq('id', customerId)
            .select()
            .single();
        savedCustomer = SupabaseServiceHelpers.asMap(res);
      } else {
        final res = await SupabaseConfig.client
            .from(SupabaseConfig.customersTable)
            .insert(customerPayload)
            .select()
            .single();
        savedCustomer = SupabaseServiceHelpers.asMap(res);
      }

      // Update auth user metadata and password (if provided)
      try {
        final rawPassword = (customerData['password'] ?? '').toString().trim();
        await SupabaseConfig.client.auth.updateUser(
          UserAttributes(
            password: rawPassword.isNotEmpty ? rawPassword : null,
            data: {
              'full_name': fullName,
              'phone': phone,
              'username': username,
            },
          ),
        );
      } catch (_) {}

      final session = await AuthSessionService.getSession();
      return {
        'success': true,
        'customer': savedCustomer,
        'user': session,
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    final identifier = username.trim();
    if (identifier.isEmpty || password.isEmpty) {
      return {
        'success': false,
        'message': 'Email or phone and password are required',
      };
    }

    try {
      if (identifier.contains('@')) {
        await SupabaseConfig.client.auth.signInWithPassword(
          email: identifier,
          password: password,
        );
      } else if (RegExp(r'^\+?[0-9][0-9 ()-]+$').hasMatch(identifier)) {
        await SupabaseConfig.client.auth.signInWithPassword(
          phone: identifier.replaceAll(RegExp(r'[ ()-]'), ''),
          password: password,
        );
      } else {
        return {
          'success': false,
          'message':
              'Supabase sign-in uses your email address or phone number. '
                  'Username-only sign-in is no longer supported.',
        };
      }

      final user = await AuthSessionService.getSession();
      if (user == null) {
        await SupabaseConfig.client.auth.signOut();
        return {
          'success': false,
          'message': 'Your account is inactive or its profile is unavailable.',
        };
      }

      return {
        'success': true,
        'user': user,
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  /// Checks if an email is already registered in the system.
  static Future<bool> checkEmailExists(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('@')) return false;

    try {
      final res = await SupabaseConfig.client.rpc(
        'check_email_registered',
        params: {'p_email': normalized},
      );
      if (res is bool) return res;
    } catch (_) {
      // If RPC is not deployed yet, check fallback in customer table
      try {
        final existing = await SupabaseConfig.client
            .from(SupabaseConfig.customersTable)
            .select('id')
            .eq('email', normalized)
            .maybeSingle();
        if (existing != null && existing.isNotEmpty) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  static Future<Map<String, dynamic>?> register(
    Map<String, dynamic> userData,
  ) async {
    final email = (userData['email'] ?? '').toString().trim();
    final password = (userData['password'] ?? '').toString();
    final fullName = (userData['full_name'] ?? '').toString().trim();
    final phone = (userData['phone'] ?? '').toString().trim();
    if (email.isEmpty || password.length < 8 || fullName.isEmpty) {
      throw Exception(
        'Full name, a valid email, and a password of at least 8 characters '
        'are required.',
      );
    }

    final username =
        (userData['username'] ?? email.split('@').first).toString().trim();
    final metadata = <String, dynamic>{
      'username': username,
      'full_name': fullName,
      'phone': phone,
      if (userData['gender'] != null) 'gender': userData['gender'],
      if (userData['date_of_birth'] != null)
        'date_of_birth': userData['date_of_birth'],
      if (userData['notes'] != null) 'notes': userData['notes'],
    };

    try {
      final response = await SupabaseConfig.client.auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );
      final authUser = response.user;
      if (authUser == null) {
        throw Exception('Supabase did not return a user after registration.');
      }

      Map<String, dynamic> customer = <String, dynamic>{};
      try {
        final customerData = await SupabaseConfig.client
            .from(SupabaseConfig.customersTable)
            .select()
            .eq('user_id', authUser.id)
            .maybeSingle();
        customer = SupabaseServiceHelpers.asMap(customerData);
      } catch (_) {
        // With email confirmation enabled there may be no authenticated
        // session yet. The database trigger still creates the customer row.
      }

      String? profilePicture;
      final rawPicture = userData['profile_picture'];
      final customerId = customer['id']?.toString();
      if (response.session != null &&
          customerId != null &&
          SupabaseStorageService.isDataImage(rawPicture)) {
        try {
          final path = await SupabaseStorageService.uploadDataImage(
            bucket: SupabaseConfig.customerAvatarsBucket,
            ownerId: customerId,
            dataUri: rawPicture.toString(),
          );
          if (path != null) {
            await SupabaseConfig.client
                .from(SupabaseConfig.customersTable)
                .update({'profile_picture': path}).eq('id', customerId);
            profilePicture = await SupabaseStorageService.resolveReference(
              bucket: SupabaseConfig.customerAvatarsBucket,
              value: path,
              isPublic: false,
            );
          }
        } catch (_) {
          // Account creation must not be rolled back because an optional image
          // failed. The customer can upload it after confirming their email.
        }
      }

      return {
        'user_id': authUser.id,
        'customer_id': customer['customer_id'] ?? customer['id'],
        'username': username,
        'full_name': customer['full_name'] ?? fullName,
        'email': authUser.email ?? email,
        'phone': customer['phone'] ?? phone,
        'profile_picture': profilePicture ?? customer['profile_picture'],
        'role': 'customer',
      };
    } catch (error) {
      throw Exception(SupabaseServiceHelpers.errorMessage(error));
    }
  }

  static final Map<String, Map<String, dynamic>> _customerCache = {};
  static List<dynamic>? _cachedCustomers;
  static DateTime? _customersCacheTime;
  static const Duration _cacheTtl = Duration(minutes: 2);

  static void invalidateCustomerCache() {
    _cachedCustomers = null;
    _customersCacheTime = null;
    _customerCache.clear();
  }

  static Future<Map<String, dynamic>?> getCustomerByUserId(String userId) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) return null;
    if (_customerCache.containsKey(cleanId)) {
      return _customerCache[cleanId];
    }
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.customersTable)
          .select()
          .eq('user_id', cleanId)
          .maybeSingle();
      if (data == null) return null;
      final normalized =
          await _normalizeCustomer(SupabaseServiceHelpers.asMap(data));
      _customerCache[cleanId] = normalized;
      final customerId = normalized['customer_id']?.toString();
      if (customerId != null && customerId.isNotEmpty) {
        _customerCache[customerId] = normalized;
      }
      return normalized;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getCustomerById(String customerId) async {
    final cleanId = customerId.trim();
    if (cleanId.isEmpty) return null;
    if (_customerCache.containsKey(cleanId)) {
      return _customerCache[cleanId];
    }
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.customersTable)
          .select()
          .eq('id', cleanId)
          .maybeSingle();
      if (data == null) return null;
      final normalized =
          await _normalizeCustomer(SupabaseServiceHelpers.asMap(data));
      _customerCache[cleanId] = normalized;
      final userId = normalized['user_id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        _customerCache[userId] = normalized;
      }
      return normalized;
    } catch (_) {
      return null;
    }
  }

  static Future<List<dynamic>> getCustomers({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedCustomers != null &&
        _customersCacheTime != null &&
        DateTime.now().difference(_customersCacheTime!) < _cacheTtl) {
      return _cachedCustomers!;
    }
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.customersTable)
          .select()
          .order('full_name');
      final customers = SupabaseServiceHelpers.asMapList(data);
      final normalizedList =
          await Future.wait(customers.map(_normalizeCustomer));
      _cachedCustomers = normalizedList;
      _customersCacheTime = DateTime.now();
      for (final c in normalizedList) {
        final id = c['customer_id']?.toString();
        final uid = c['user_id']?.toString();
        if (id != null && id.isNotEmpty) _customerCache[id] = c;
        if (uid != null && uid.isNotEmpty) _customerCache[uid] = c;
      }
      return normalizedList;
    } catch (_) {
      return <dynamic>[];
    }
  }

  static Future<Map<String, dynamic>> _normalizeCustomer(
    Map<String, dynamic> row,
  ) async {
    final customer = Map<String, dynamic>.from(row);
    customer['customer_id'] = customer['customer_id'] ?? customer['id'];
    final photo = await SupabaseStorageService.resolveReference(
      bucket: SupabaseConfig.customerAvatarsBucket,
      value: customer['profile_picture'],
      isPublic: false,
    );
    if (photo != null) customer['profile_picture'] = photo;
    return customer;
  }

  static Future<List<dynamic>> getAppointments({
    String? customerId,
    bool upcomingOnly = false,
  }) {
    return _queryAppointments(
      customerId: customerId,
      upcomingOnly: upcomingOnly,
    );
  }

  static Future<List<dynamic>> _queryAppointments({
    String? customerId,
    String? staffId,
    String? appointmentId,
    String? date,
    bool upcomingOnly = false,
  }) async {
    try {
      dynamic query = SupabaseConfig.client
          .from(SupabaseConfig.appointmentDetailsView)
          .select();
      if (customerId != null && customerId.isNotEmpty) {
        query = query.eq('customer_id', customerId);
      }
      if (staffId != null && staffId.isNotEmpty) {
        query = query.eq('staff_id', staffId);
      }
      if (appointmentId != null && appointmentId.isNotEmpty) {
        query = query.eq('appointment_id', appointmentId);
      }

      if (date == 'today') {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final end = start.add(const Duration(days: 1));
        query = query
            .gte('start_time', start.toUtc().toIso8601String())
            .lt('start_time', end.toUtc().toIso8601String());
      } else if (date != null && date.isNotEmpty && date != 'all') {
        final day = DateTime.tryParse(date);
        if (day != null) {
          final start = DateTime(day.year, day.month, day.day);
          query = query.gte('start_time', start.toUtc().toIso8601String()).lt(
                'start_time',
                start.add(const Duration(days: 1)).toUtc().toIso8601String(),
              );
        }
      }

      if (upcomingOnly) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        query = query.gte(
          'start_time',
          today.toUtc().toIso8601String(),
        );
      }
      if (customerId == null && staffId == null && appointmentId == null) {
        query = query.neq('status', 'canceled');
      }

      final data = await query.order(
        'start_time',
        ascending: upcomingOnly || staffId != null || date == 'today',
      );
      final rows = SupabaseServiceHelpers.asMapList(data);
      return Future.wait(rows.map(_normalizeAppointment));
    } catch (_) {
      return <dynamic>[];
    }
  }

  static Future<Map<String, dynamic>> _normalizeAppointment(
    Map<String, dynamic> row,
  ) async {
    final appointment = Map<String, dynamic>.from(row);
    appointment['appointment_id'] =
        appointment['appointment_id'] ?? appointment['id'];

    final start = SupabaseServiceHelpers.parseDateTime(
      appointment['start_time'],
    );
    if (start != null) {
      appointment['date'] = SupabaseServiceHelpers.displayDate(start);
      appointment['time'] = SupabaseServiceHelpers.displayTime(start);
    }

    appointment['service_price'] = appointment['service_price'] ??
        appointment['price'] ??
        appointment['service_cost'] ??
        0;
    appointment['service_image'] = appointment['service_image'] ??
        appointment['service_image_url'] ??
        appointment['image_url'];

    final serviceImage = await SupabaseStorageService.resolveReference(
      bucket: SupabaseConfig.serviceImagesBucket,
      value: appointment['service_image'],
      isPublic: true,
    );
    if (serviceImage != null) {
      appointment['service_image'] = serviceImage;
      appointment['image_url'] = serviceImage;
    }

    final staffPhoto = await SupabaseStorageService.resolveReference(
      bucket: SupabaseConfig.staffAvatarsBucket,
      value: appointment['staff_photo'] ?? appointment['staff_profile_photo'],
      isPublic: true,
    );
    if (staffPhoto != null) appointment['staff_photo'] = staffPhoto;

    final customerPhoto = await SupabaseStorageService.resolveReference(
      bucket: SupabaseConfig.customerAvatarsBucket,
      value: appointment['customer_photo'] ??
          appointment['customer_profile_picture'],
      isPublic: false,
    );
    if (customerPhoto != null) appointment['customer_photo'] = customerPhoto;
    return appointment;
  }

  static Future<Map<String, dynamic>?> getAppointmentById(
    String appointmentId,
  ) async {
    final rows = await _queryAppointments(appointmentId: appointmentId);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);
  }

  static Future<Map<String, dynamic>?> createAppointment(
    Map<String, dynamic> appointmentData,
  ) async {
    try {
      final startTime = SupabaseServiceHelpers.toUtcIso(
        appointmentData['start_time'],
      );
      final result = await SupabaseConfig.client.rpc(
        SupabaseConfig.createAppointmentRpc,
        params: {
          'p_staff_id': appointmentData['staff_id'],
          'p_service_id': appointmentData['service_id'],
          'p_start_time': startTime,
          'p_notes': appointmentData['notes'],
        },
      );
      return _mutationData(result, idKey: 'appointment_id');
    } catch (error) {
      final errStr = error.toString().toLowerCase();
      if (errStr.contains('23p01') ||
          errStr.contains('not available') ||
          errStr.contains('overlap') ||
          errStr.contains('exclusion')) {
        throw Exception(
          'This barber is already booked at that time. Please select another time or barber.',
        );
      }

      if (!SupabaseServiceHelpers.isMissingDatabaseObject(error)) {
        throw Exception(SupabaseServiceHelpers.errorMessage(error));
      }

      // Development fallback for a project whose RPC migration has not yet
      // been applied. Production should always use create_appointment.
      try {
        final insert = <String, dynamic>{
          'customer_id': appointmentData['customer_id'],
          'staff_id': appointmentData['staff_id'],
          'service_id': appointmentData['service_id'],
          'start_time': SupabaseServiceHelpers.toUtcIso(
            appointmentData['start_time'],
          ),
          if (appointmentData['end_time'] != null)
            'end_time': SupabaseServiceHelpers.toUtcIso(
              appointmentData['end_time'],
            ),
          'status': appointmentData['status'] ?? 'pending',
          'notes': appointmentData['notes'],
        };
        final data = await SupabaseConfig.client
            .from(SupabaseConfig.appointmentsTable)
            .insert(insert)
            .select()
            .single();
        return _mutationData(data, idKey: 'appointment_id');
      } catch (insertErr) {
        final insertErrStr = insertErr.toString().toLowerCase();
        if (insertErrStr.contains('23p01') ||
            insertErrStr.contains('overlap') ||
            insertErrStr.contains('exclusion')) {
          throw Exception(
            'This barber is already booked at that time. Please select another time or barber.',
          );
        }
        throw Exception(SupabaseServiceHelpers.errorMessage(insertErr));
      }
    }
  }

  static Future<List<dynamic>> getCustomerAppointments(
    String customerId,
  ) =>
      getAppointments(customerId: customerId);

  static Future<Map<String, dynamic>?> getCustomerProfile(
    String customerId,
  ) async {
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.customersTable)
          .select()
          .eq('id', customerId)
          .maybeSingle();
      final customer = SupabaseServiceHelpers.asMap(data);
      return customer.isEmpty ? null : _normalizeCustomer(customer);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> updateCustomerProfile(
    String customerId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      var resolvedCustomerId = customerId;
      if (resolvedCustomerId.isEmpty) {
        final userId = (profileData['user_id'] ??
                SupabaseConfig.client.auth.currentUser?.id ??
                '')
            .toString();
        if (userId.isNotEmpty) {
          final row = await SupabaseConfig.client
              .from(SupabaseConfig.customersTable)
              .select('id')
              .eq('user_id', userId)
              .maybeSingle();
          resolvedCustomerId =
              SupabaseServiceHelpers.asMap(row)['id']?.toString() ?? '';
        }
      }
      if (resolvedCustomerId.isEmpty) {
        throw Exception('Customer profile was not found.');
      }

      final update = <String, dynamic>{};
      for (final field in const [
        'full_name',
        'phone',
        'email',
        'gender',
        'date_of_birth',
        'notes',
      ]) {
        if (profileData.containsKey(field)) update[field] = profileData[field];
      }

      final picture = profileData['profile_picture'];
      if (SupabaseStorageService.isDataImage(picture)) {
        update['profile_picture'] =
            await SupabaseStorageService.uploadDataImage(
          bucket: SupabaseConfig.customerAvatarsBucket,
          ownerId: resolvedCustomerId,
          dataUri: picture.toString(),
        );
      } else if (profileData.containsKey('profile_picture')) {
        update['profile_picture'] = picture == '' ? null : picture;
      }

      final data = await SupabaseConfig.client
          .from(SupabaseConfig.customersTable)
          .update(update)
          .eq('id', resolvedCustomerId)
          .select()
          .single();
      return _normalizeCustomer(SupabaseServiceHelpers.asMap(data));
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> updateAppointment(
    String appointmentId,
    Map<String, dynamic> appointmentData,
  ) async {
    try {
      if (appointmentData['date'] != null && appointmentData['time'] != null) {
        final localStart = DateTime.tryParse(
          '${appointmentData['date']}T${appointmentData['time']}',
        );
        if (localStart == null)
          throw Exception('Invalid appointment date/time.');
        final result = await SupabaseConfig.client.rpc(
          SupabaseConfig.rescheduleAppointmentRpc,
          params: {
            'p_appointment_id': appointmentId,
            'p_start_time': localStart.toUtc().toIso8601String(),
            'p_staff_id': appointmentData['staff_id'],
          },
        );
        return {
          'success': true,
          'data': _mutationData(result, idKey: 'appointment_id'),
        };
      }

      if (appointmentData.length == 1 &&
          appointmentData.containsKey('status')) {
        final status = appointmentData['status']?.toString().toLowerCase();
        final rpc = status == 'canceled' || status == 'cancelled'
            ? SupabaseConfig.cancelAppointmentRpc
            : SupabaseConfig.setAppointmentStatusRpc;
        final params = <String, dynamic>{
          'p_appointment_id': appointmentId,
          if (rpc == SupabaseConfig.setAppointmentStatusRpc) 'p_status': status,
        };
        final result = await SupabaseConfig.client.rpc(rpc, params: params);
        return {
          'success': true,
          'data': _mutationData(result, idKey: 'appointment_id'),
        };
      }

      if (appointmentData.length == 1 && appointmentData.containsKey('notes')) {
        final result = await SupabaseConfig.client.rpc(
          SupabaseConfig.updateAppointmentNotesRpc,
          params: {
            'p_appointment_id': appointmentId,
            'p_notes': appointmentData['notes']?.toString(),
          },
        );
        return {
          'success': true,
          'data': _mutationData(result, idKey: 'appointment_id'),
        };
      }

      final update = <String, dynamic>{};
      for (final field in const [
        'status',
        'notes',
        'customer_id',
        'staff_id',
        'service_id',
        'start_time',
        'end_time',
      ]) {
        if (appointmentData.containsKey(field)) {
          final value = appointmentData[field];
          update[field] = (field == 'start_time' || field == 'end_time')
              ? SupabaseServiceHelpers.toUtcIso(value)
              : value;
        }
      }
      if (update.isEmpty) throw Exception('No appointment fields to update.');

      final data = await SupabaseConfig.client
          .from(SupabaseConfig.appointmentsTable)
          .update(update)
          .eq('id', appointmentId)
          .select()
          .single();
      final result = SupabaseServiceHelpers.asMap(data);
      result['appointment_id'] = result['appointment_id'] ?? result['id'];
      return {'success': true, 'data': result};
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<bool> hasFeedback(
    String appointmentId,
    String customerId,
  ) async {
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.feedbackTable)
          .select('id')
          .eq('appointment_id', appointmentId)
          .eq('customer_id', customerId)
          .limit(1);
      return data.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> submitFeedback({
    required String appointmentId,
    required String customerId,
    required int rating,
    String? comments,
  }) async {
    if (rating < 1 || rating > 5) {
      return {'success': false, 'message': 'Rating must be between 1 and 5.'};
    }
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.feedbackTable)
          .upsert(
            {
              'appointment_id': appointmentId,
              'customer_id': customerId,
              'rating': rating,
              'comments': comments,
            },
            onConflict: 'appointment_id,customer_id',
          )
          .select()
          .single();
      return {
        'success': true,
        'message': 'Feedback submitted successfully',
        'data': data,
      };
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Map<String, dynamic>? _mutationData(
    dynamic value, {
    required String idKey,
  }) {
    if (value == null) return null;
    if (value is List && value.isNotEmpty) {
      return _mutationData(value.first, idKey: idKey);
    }
    final map = SupabaseServiceHelpers.asMap(value);
    if (map.isNotEmpty) {
      if (map['data'] is Map) {
        return _mutationData(map['data'], idKey: idKey);
      }
      map[idKey] = map[idKey] ?? map['id'];
      return map;
    }
    if (value is String) return {idKey: value};
    return null;
  }
}

/// Dispatches the old logical endpoint strings to direct Supabase operations.
/// This keeps the remaining un-migrated widgets functional without PHP/http.
class ApiServiceExtension {
  ApiServiceExtension._();

  static Future<Map<String, dynamic>> get(String url) async {
    try {
      final uri = Uri.parse(url);
      final resource = _resource(uri);
      if (resource == 'appointments') {
        final rows = await ApiService._queryAppointments(
          customerId: uri.queryParameters['customer_id'],
          staffId: uri.queryParameters['staff_id'],
          appointmentId: uri.queryParameters['appointment_id'],
          date: uri.queryParameters['date'],
          upcomingOnly: uri.queryParameters['upcoming_only'] == '1',
        );
        return {'success': true, 'data': rows};
      }
      if (resource == 'customers') {
        final rows = await ApiService.getCustomers();
        return {'success': true, 'data': rows};
      }
      throw UnsupportedError('Unsupported Supabase resource: $resource');
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> post(
    String url,
    Map<String, dynamic> data,
  ) async {
    try {
      final resource = _resource(Uri.parse(url));
      if (resource == 'appointments') {
        final result = await ApiService.createAppointment(data);
        return result == null
            ? {'success': false, 'message': 'Failed to create appointment'}
            : {'success': true, 'data': result};
      }
      throw UnsupportedError('Unsupported Supabase resource: $resource');
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> put(
    String url,
    Map<String, dynamic> data,
  ) async {
    try {
      final resource = _resource(Uri.parse(url));
      if (resource == 'appointments') {
        final appointmentId = (data['appointment_id'] ?? '').toString();
        return ApiService.updateAppointment(appointmentId, data);
      }
      if (resource == 'customers') {
        final customerId = (data['customer_id'] ?? '').toString();
        final result = await ApiService.updateCustomerProfile(customerId, data);
        return result == null
            ? {'success': false, 'message': 'Failed to update customer profile'}
            : {'success': true, 'data': result};
      }
      throw UnsupportedError('Unsupported Supabase resource: $resource');
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<Map<String, dynamic>> delete(
    String url,
    Map<String, dynamic>? data,
  ) async {
    try {
      final resource = _resource(Uri.parse(url));
      if (resource == 'appointments') {
        final appointmentId = (data?['appointment_id'] ?? '').toString();
        return ApiService.updateAppointment(
          appointmentId,
          {'status': 'canceled'},
        );
      }
      throw UnsupportedError('Unsupported Supabase resource: $resource');
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static String _resource(Uri uri) {
    for (final segment in uri.pathSegments.reversed) {
      final normalized = segment.replaceAll('.php', '').toLowerCase();
      if (const {
        'appointments',
        'customers',
        'employees',
        'services',
        'categories',
        'feedback',
        'transactions',
      }.contains(normalized)) {
        return normalized;
      }
    }
    return uri.host.toLowerCase();
  }
}
