import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/api_config.dart';
import 'supabase_service_helpers.dart';

/// Adapts Supabase Auth's persisted session to the legacy user-map contract.
///
/// `supabase_flutter` persists and refreshes the access token itself. Profile
/// data is always reloaded under RLS and is never treated as an
/// authentication credential.
class AuthSessionService {
  AuthSessionService._();

  // Kept for compatibility with existing callers. Supabase persists the
  // authenticated session; profile rows are reloaded by [getSession].
  static Future<void> saveSession(Map<String, dynamic> userData) =>
      Future<void>.value();

  /// Returns null when signed out. Throws when the profile cannot be loaded
  /// (e.g. no connection) so callers can offer a retry instead of routing a
  /// staff member to the customer onboarding flow.
  static Future<Map<String, dynamic>?> getSession() async {
    User? authUser;
    try {
      final userRes = await SupabaseConfig.client.auth.getUser();
      authUser = userRes.user ?? SupabaseConfig.client.auth.currentUser;
    } catch (_) {
      authUser = SupabaseConfig.client.auth.currentUser;
    }
    if (authUser == null) {
      return null;
    }

    // If email confirmation is required but not yet done, don't create a session
    final isEmailProvider = authUser.appMetadata['provider'] == 'email' ||
        (authUser.appMetadata['providers'] as List?)?.contains('email') == true;
    if (isEmailProvider &&
        authUser.emailConfirmedAt == null) {
      // Unconfirmed email — sign out and return null so the UI stays on login
      try { await SupabaseConfig.client.auth.signOut(); } catch (_) {}
      return null;
    }

    final meta = authUser.userMetadata ?? {};
    final username = meta['username'] ?? _usernameFromEmail(authUser.email);
    final fullName = meta['full_name'] ?? meta['name'] ?? username;
    final photoRef = meta['avatar_url'] ?? meta['profile_picture'] ?? meta['profile_photo'];

    final session = <String, dynamic>{
      'user_id': authUser.id,
      'username': username,
      'full_name': fullName,
      'email': authUser.email,
      'phone': authUser.phone ?? meta['phone'],
      'role': 'customer',
      'is_active': true,
      'profile_photo': photoRef ?? 'assets/images/admin_fes.jpg',
      'profile_picture': photoRef ?? 'assets/images/admin_fes.jpg',
      'is_profile_completed': false,
    };

    // Network/server errors propagate: the role must come from the database.
    final profileData = await SupabaseConfig.client
        .from(SupabaseConfig.profilesTable)
        .select()
        .eq('id', authUser.id)
        .maybeSingle();
    final profile = SupabaseServiceHelpers.asMap(profileData);

    if (profile.isNotEmpty) {
      final isActive = SupabaseServiceHelpers.asBool(profile['is_active'], true);
      if (!isActive) {
        await SupabaseConfig.client.auth.signOut();
        return null;
      }

      session['username'] = profile['username'] ?? session['username'];
      final dbRole = (profile['role'] ?? '').toString().toLowerCase();
      if (const {'admin', 'manager', 'cashier', 'barber', 'staff'}
          .contains(dbRole)) {
        session['role'] = dbRole;
      }
    }

    final role = session['role'] as String;

    if (role == 'admin' || role == 'manager' || role == 'cashier') {
      session['is_profile_completed'] = true;
      return session;
    }

    if (role == 'barber' || role == 'staff') {
      final staffData = await SupabaseConfig.client
          .from(SupabaseConfig.staffTable)
          .select()
          .eq('user_id', authUser.id)
          .maybeSingle();
      final staff = SupabaseServiceHelpers.asMap(staffData);
      if (staff.isNotEmpty) {
        final photo = await SupabaseStorageService.resolveReference(
          bucket: SupabaseConfig.staffAvatarsBucket,
          value: staff['profile_photo'],
          isPublic: true,
        );
        final staffRole = staff['role'];
        session.addAll(staff);
        session['staff_id'] = staff['staff_id'] ?? staff['id'];
        session['user_id'] = authUser.id;
        session['staff_role'] = staffRole;
        session['role'] = role;
        if (photo != null) session['profile_photo'] = photo;
      }
      session['is_profile_completed'] = true;
      return session;
    }

    // Customer role: check if profile is completed
    final customerData = await SupabaseConfig.client
        .from(SupabaseConfig.customersTable)
        .select()
        .eq('user_id', authUser.id)
        .maybeSingle();
    final customer = SupabaseServiceHelpers.asMap(customerData);

    if (customer.isNotEmpty) {
      final photo = await SupabaseStorageService.resolveReference(
        bucket: SupabaseConfig.customerAvatarsBucket,
        value: customer['profile_picture'],
        isPublic: false,
      );
      session.addAll(customer);
      session['customer_id'] =
          customer['customer_id'] ?? customer['id'] ?? authUser.id;
      session['user_id'] = authUser.id;
      if (photo != null) {
        session['profile_picture'] = photo;
        session['profile_photo'] = photo;
      }
      session['role'] = 'customer';
      final phone = (customer['phone'] ?? '').toString().trim();
      final fullNameVal = (customer['full_name'] ?? '').toString().trim();
      // Profile is completed only if phone is set and not placeholder
      session['is_profile_completed'] = phone.isNotEmpty &&
          phone != '0000000000' &&
          fullNameVal.isNotEmpty &&
          fullNameVal != 'Customer';
    } else {
      // No customer record exists yet -> first time user!
      session['role'] = 'customer';
      session['customer_id'] = authUser.id;
      session['is_profile_completed'] = false;
    }

    return session;
  }

  static Future<void> clearSession() async {
    await SupabaseConfig.client.auth.signOut();
  }

  static String _usernameFromEmail(String? email) {
    if (email == null || email.isEmpty) return 'User';
    return email.split('@').first;
  }
}
