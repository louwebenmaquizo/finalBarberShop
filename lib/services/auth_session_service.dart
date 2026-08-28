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

  static Future<Map<String, dynamic>?> getSession() async {
    final authUser = SupabaseConfig.client.auth.currentUser;
    if (authUser == null) {
      return null;
    }

    try {
      final profileData = await SupabaseConfig.client
          .from(SupabaseConfig.profilesTable)
          .select()
          .eq('id', authUser.id)
          .maybeSingle();
      final profile = SupabaseServiceHelpers.asMap(profileData);

      if (profile.isEmpty) {
        await SupabaseConfig.client.auth.signOut();
        return null;
      }

      final isActive = SupabaseServiceHelpers.asBool(
        profile['is_active'],
        false,
      );
      if (!isActive) {
        await SupabaseConfig.client.auth.signOut();
        return null;
      }

      final role = profile['role']?.toString().toLowerCase();
      if (role == null || role.isEmpty) {
        await SupabaseConfig.client.auth.signOut();
        return null;
      }

      final session = <String, dynamic>{
        'user_id': authUser.id,
        'username': profile['username'] ?? _usernameFromEmail(authUser.email),
        'email': authUser.email,
        'phone': authUser.phone,
        'role': role,
        'is_active': isActive,
      };

      if (role == 'customer') {
        final customerData = await SupabaseConfig.client
            .from(SupabaseConfig.customersTable)
            .select()
            .eq('user_id', authUser.id)
            .maybeSingle();
        final customer = SupabaseServiceHelpers.asMap(customerData);
        if (customer.isEmpty) {
          await SupabaseConfig.client.auth.signOut();
          return null;
        }
        final photo = await SupabaseStorageService.resolveReference(
          bucket: SupabaseConfig.customerAvatarsBucket,
          value: customer['profile_picture'],
          isPublic: false,
        );
        session.addAll(customer);
        session['customer_id'] = customer['customer_id'] ?? customer['id'];
        session['user_id'] = authUser.id;
        if (photo != null) {
          session['profile_picture'] = photo;
          session['profile_photo'] = photo;
        }
        session['role'] = 'customer';
      } else if (role == 'barber' || role == 'staff') {
        final staffData = await SupabaseConfig.client
            .from(SupabaseConfig.staffTable)
            .select()
            .eq('user_id', authUser.id)
            .maybeSingle();
        final staff = SupabaseServiceHelpers.asMap(staffData);
        if (staff.isEmpty) {
          await SupabaseConfig.client.auth.signOut();
          return null;
        }
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

      return session;
    } catch (_) {
      await SupabaseConfig.client.auth.signOut();
      return null;
    }
  }

  static Future<void> clearSession() async {
    await SupabaseConfig.client.auth.signOut();
  }

  static String _usernameFromEmail(String? email) {
    if (email == null || email.isEmpty) return 'User';
    return email.split('@').first;
  }
}
