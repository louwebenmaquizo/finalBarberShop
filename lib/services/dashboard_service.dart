import '../config/api_config.dart';
import 'api_service.dart' show ApiServiceExtension;

/// Dashboard Service
/// Contains all functions for dashboard-related operations
/// One function per screen/feature
class DashboardService {
  // Dashboard Screen Functions
  
  /// Get all dashboard data (stats, analytics, bookings, barbers)
  /// Used for the main dashboard screen
  static Future<Map<String, dynamic>?> getDashboardData() async {
    try {
      final response = await ApiServiceExtension.get('${ApiConfig.baseUrl}/dashboard.php');
      
      if (response['success'] == true && response['data'] != null) {
        return response['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Error fetching dashboard data: $e');
      return null;
    }
  }
  
  /// Get dashboard statistics only
  /// Returns: today_bookings, total_bookings, total_barbers, revenue_today
  static Future<Map<String, dynamic>?> getDashboardStats() async {
    try {
      final data = await getDashboardData();
      return data?['stats'] as Map<String, dynamic>?;
    } catch (e) {
      print('Error fetching dashboard stats: $e');
      return null;
    }
  }
  
  /// Get analytics data for the graph
  /// Returns: days array and values array
  static Future<Map<String, dynamic>?> getAnalyticsData() async {
    try {
      final data = await getDashboardData();
      return data?['analytics'] as Map<String, dynamic>?;
    } catch (e) {
      print('Error fetching analytics data: $e');
      return null;
    }
  }
  
  /// Get next client (upcoming appointment)
  /// Returns: customer_name, date, time
  static Future<Map<String, dynamic>?> getNextClient() async {
    try {
      final data = await getDashboardData();
      return data?['next_client'] as Map<String, dynamic>?;
    } catch (e) {
      print('Error fetching next client: $e');
      return null;
    }
  }
  
  /// Get recent bookings (last 8)
  /// Returns: List of booking objects with time, customer, service, schedule, employee
  static Future<List<Map<String, dynamic>>> getRecentBookings() async {
    try {
      final data = await getDashboardData();
      final bookings = data?['recent_bookings'] as List<dynamic>?;
      return bookings?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      print('Error fetching recent bookings: $e');
      return [];
    }
  }
  
  /// Get top-rated barbers (active staff, limited to 4)
  /// Returns: List of barber objects with name and role
  static Future<List<Map<String, dynamic>>> getTopBarbers() async {
    try {
      final data = await getDashboardData();
      final barbers = data?['top_barbers'] as List<dynamic>?;
      return barbers?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      print('Error fetching top barbers: $e');
      return [];
    }
  }
}

