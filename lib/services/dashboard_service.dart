import '../config/api_config.dart';
import 'supabase_service_helpers.dart';

class DashboardService {
  DashboardService._();

  static Future<Map<String, dynamic>?> getDashboardData() async {
    try {
      final raw = await SupabaseConfig.client.rpc(SupabaseConfig.dashboardRpc);
      final data = SupabaseServiceHelpers.asMap(raw);
      if (data.isEmpty) return null;

      final barbers = SupabaseServiceHelpers.asMapList(data['top_barbers']);
      data['top_barbers'] = await Future.wait(barbers.map((barber) async {
        final photo = await SupabaseStorageService.resolveReference(
          bucket: SupabaseConfig.staffAvatarsBucket,
          value: barber['profile_photo'],
          isPublic: true,
        );
        if (photo != null) barber['profile_photo'] = photo;
        return barber;
      }));
      data['recent_bookings'] =
          SupabaseServiceHelpers.asMapList(data['recent_bookings']);
      data['monthly_revenue'] =
          SupabaseServiceHelpers.asMapList(data['monthly_revenue']);
      return data;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getDashboardStats() async {
    final data = await getDashboardData();
    final stats = SupabaseServiceHelpers.asMap(data?['stats']);
    return stats.isEmpty ? null : stats;
  }

  static Future<Map<String, dynamic>?> getAnalyticsData() async {
    final data = await getDashboardData();
    final analytics = SupabaseServiceHelpers.asMap(data?['analytics']);
    return analytics.isEmpty ? null : analytics;
  }

  static Future<Map<String, dynamic>?> getNextClient() async {
    final data = await getDashboardData();
    final client = SupabaseServiceHelpers.asMap(data?['next_client']);
    return client.isEmpty ? null : client;
  }

  static Future<List<Map<String, dynamic>>> getRecentBookings() async {
    final data = await getDashboardData();
    return SupabaseServiceHelpers.asMapList(data?['recent_bookings']);
  }

  static Future<List<Map<String, dynamic>>> getTopBarbers() async {
    final data = await getDashboardData();
    return SupabaseServiceHelpers.asMapList(data?['top_barbers']);
  }
}
