import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'supabase_service_helpers.dart';

/// Representation of an in-app notification grounded in live database data.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
  bool isRead;
  final String type; // 'booking', 'status', 'summary', 'reminder', 'offer'
  final Map<String, dynamic>? metadata;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.icon,
    required this.color,
    this.isRead = false,
    this.type = 'booking',
    this.metadata,
  });

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.isNegative) {
      // Future appointment date/time
      final inDays = (-difference.inDays);
      final inHours = (-difference.inHours);
      if (inDays > 1) return 'In $inDays days';
      if (inDays == 1) return 'Tomorrow';
      if (inHours > 0) return 'In $inHours hours';
      return 'Coming up soon';
    }

    if (difference.inDays > 7) {
      return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
    } else if (difference.inDays >= 2) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'min' : 'mins'} ago';
    } else {
      return 'Just now';
    }
  }
}

/// Service providing live, grounded notifications for Admins, Barbers, and Customers.
class NotificationService {
  NotificationService._();

  static final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);

  static String get _currentUid {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid != null && uid.trim().isNotEmpty) {
      return uid.trim();
    }
    return 'guest';
  }

  static String get _readKey => 'notifications_read_v2_$_currentUid';
  static String get _clearedKey => 'notifications_cleared_v2_$_currentUid';

  /// Fetches grounded, dynamic notifications from the database.
  static Future<List<AppNotification>> getNotifications({
    bool isAdmin = false,
    String? customerId,
    String? staffId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final readIds = (prefs.getStringList(_readKey) ?? []).toSet();
    final clearedIds = (prefs.getStringList(_clearedKey) ?? []).toSet();

    final notifications = <AppNotification>[];

    try {
      if (isAdmin) {
        await _generateAdminNotifications(notifications);
      } else if (customerId != null && customerId.isNotEmpty) {
        await _generateCustomerNotifications(notifications, customerId);
      } else if (staffId != null && staffId.isNotEmpty) {
        await _generateStaffNotifications(notifications, staffId);
      } else {
        await _generateCustomerNotifications(notifications, null);
      }
    } catch (e) {
      debugPrint('Error generating dynamic notifications: $e');
    }

    // Filter out cleared notifications and apply read status
    final filtered = notifications.where((n) => !clearedIds.contains(n.id)).toList();
    for (final item in filtered) {
      if (readIds.contains(item.id)) {
        item.isRead = true;
      }
    }

    // Sort newest first
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Update unread count notifier
    final unread = filtered.where((n) => !n.isRead).length;
    unreadCountNotifier.value = unread;

    return filtered;
  }

  /// Refreshes the badge count in background.
  static Future<int> refreshUnreadCount({
    bool isAdmin = false,
    String? customerId,
    String? staffId,
  }) async {
    final list = await getNotifications(
      isAdmin: isAdmin,
      customerId: customerId,
      staffId: staffId,
    );
    final count = list.where((n) => !n.isRead).length;
    unreadCountNotifier.value = count;
    return count;
  }

  static Future<void> markAsRead(String notificationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final readIds = (prefs.getStringList(_readKey) ?? []).toSet();
      readIds.add(notificationId);
      await prefs.setStringList(_readKey, readIds.toList());

      if (unreadCountNotifier.value > 0) {
        unreadCountNotifier.value = unreadCountNotifier.value - 1;
      }
    } catch (_) {}
  }

  static Future<void> markAllAsRead(List<AppNotification> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final readIds = (prefs.getStringList(_readKey) ?? []).toSet();
      for (final n in list) {
        n.isRead = true;
        readIds.add(n.id);
      }
      await prefs.setStringList(_readKey, readIds.toList());
      unreadCountNotifier.value = 0;
    } catch (_) {}
  }

  static Future<void> clearAll(List<AppNotification> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clearedIds = (prefs.getStringList(_clearedKey) ?? []).toSet();
      for (final n in list) {
        clearedIds.add(n.id);
      }
      await prefs.setStringList(_clearedKey, clearedIds.toList());
      unreadCountNotifier.value = 0;
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ADMIN NOTIFICATIONS GENERATION
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _generateAdminNotifications(
      List<AppNotification> output) async {
    final now = DateTime.now();

    // 1. Fetch recent appointments from Supabase
    List<Map<String, dynamic>> appointments = [];
    try {
      final res = await SupabaseConfig.client
          .from(SupabaseConfig.appointmentDetailsView)
          .select()
          .order('start_time', ascending: false)
          .limit(20);
      appointments = SupabaseServiceHelpers.asMapList(res);
    } catch (e) {
      debugPrint('Error loading appointments for notifications: $e');
    }

    // 2. Add Daily Operations Snapshot
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final todayAppts = appointments.where((a) {
      final st = SupabaseServiceHelpers.parseDateTime(a['start_time']);
      return st != null && st.isAfter(todayStart) && st.isBefore(todayEnd);
    }).toList();

    double todayRevenue = 0.0;
    for (final a in todayAppts) {
      if (a['status'] == 'completed') {
        todayRevenue += (num.tryParse(a['price']?.toString() ?? '0') ?? 0).toDouble();
      }
    }

    output.add(AppNotification(
      id: 'daily_summary_${todayStart.toIso8601String().split('T').first}',
      title: 'Daily Operations Summary 📊',
      body: todayAppts.isEmpty
          ? 'Store schedule open. Ready for appointments today.'
          : '${todayAppts.length} appointments today. Total completed revenue: ₱${todayRevenue.toStringAsFixed(2)}.',
      timestamp: todayStart.add(const Duration(hours: 8)),
      icon: Icons.insights_rounded,
      color: const Color(0xFF1E88E5),
      type: 'summary',
    ));

    // 3. Add Individual Appointment Notifications
    for (final appt in appointments) {
      final id = (appt['appointment_id'] ?? appt['id'] ?? '').toString();
      final customerName = appt['customer_name']?.toString() ?? 'A client';
      final serviceName = appt['service_name']?.toString() ?? 'Haircut Service';
      final staffName = appt['staff_name']?.toString() ?? 'Assigned Barber';
      final status = (appt['status']?.toString() ?? 'booked').toLowerCase();
      final startTime = SupabaseServiceHelpers.parseDateTime(appt['start_time']) ?? now;
      final timeStr = _formatFriendlyDateTime(startTime);

      if (status == 'completed') {
        output.add(AppNotification(
          id: 'appt_done_${id}_completed',
          title: 'Appointment Completed ✂️',
          body: '$customerName\'s "$serviceName" with $staffName has been marked completed.',
          timestamp: startTime.add(const Duration(minutes: 45)),
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF10B981),
          type: 'status',
          metadata: appt,
        ));
      } else if (status == 'canceled' || status == 'declined') {
        output.add(AppNotification(
          id: 'appt_cancel_${id}_$status',
          title: 'Appointment Canceled',
          body: 'Booking for $customerName ("$serviceName") on $timeStr was canceled.',
          timestamp: startTime,
          icon: Icons.cancel_rounded,
          color: Colors.redAccent,
          type: 'status',
          metadata: appt,
        ));
      } else {
        // Booked / Confirmed / Upcoming
        output.add(AppNotification(
          id: 'appt_new_${id}_$status',
          title: 'New Appointment Booked 📅',
          body: '$customerName booked "$serviceName" with $staffName for $timeStr.',
          timestamp: startTime.isAfter(now) ? now.subtract(const Duration(minutes: 15)) : startTime,
          icon: Icons.calendar_today_rounded,
          color: const Color(0xFF1E88E5),
          type: 'booking',
          metadata: appt,
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CUSTOMER NOTIFICATIONS GENERATION
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _generateCustomerNotifications(
      List<AppNotification> output, String? customerId) async {
    final now = DateTime.now();

    List<Map<String, dynamic>> appointments = [];
    if (customerId != null && customerId.isNotEmpty) {
      try {
        final res = await SupabaseConfig.client
            .from(SupabaseConfig.appointmentDetailsView)
            .select()
            .eq('customer_id', customerId)
            .order('start_time', ascending: false)
            .limit(10);
        appointments = SupabaseServiceHelpers.asMapList(res);
      } catch (e) {
        debugPrint('Error loading customer appointments for notifications: $e');
      }
    }

    // 1. Welcome & Special Promotion Notification
    output.add(AppNotification(
      id: 'promo_welcome_liem',
      title: 'Welcome to Liem Barber Shop! 💈',
      body: 'Book top haircuts, fades, and grooming with master barbers. Check our catalog for latest styles.',
      timestamp: now.subtract(const Duration(hours: 4)),
      icon: Icons.local_offer_rounded,
      color: const Color(0xFF5BBCFF),
      type: 'offer',
    ));

    // 2. Appointment-based customer notifications
    for (final appt in appointments) {
      final id = (appt['appointment_id'] ?? appt['id'] ?? '').toString();
      final serviceName = appt['service_name']?.toString() ?? 'Haircut';
      final staffName = appt['staff_name']?.toString() ?? 'Barber';
      final status = (appt['status']?.toString() ?? 'booked').toLowerCase();
      final startTime = SupabaseServiceHelpers.parseDateTime(appt['start_time']) ?? now;
      final timeStr = _formatFriendlyDateTime(startTime);

      if (status == 'completed') {
        output.add(AppNotification(
          id: 'cust_appt_done_$id',
          title: 'Thank You for Visiting! ✂️',
          body: 'Your "$serviceName" with $staffName is complete. Hope you look sharp! Leave a review anytime.',
          timestamp: startTime.add(const Duration(minutes: 30)),
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF10B981),
          type: 'status',
          metadata: appt,
        ));
      } else if (status == 'canceled') {
        output.add(AppNotification(
          id: 'cust_appt_cancel_$id',
          title: 'Appointment Canceled',
          body: 'Your booking for "$serviceName" on $timeStr has been canceled.',
          timestamp: startTime,
          icon: Icons.info_outline_rounded,
          color: Colors.redAccent,
          type: 'status',
          metadata: appt,
        ));
      } else {
        // Confirmed / Upcoming
        final isUpcomingSoon = startTime.isAfter(now) &&
            startTime.isBefore(now.add(const Duration(hours: 36)));

        if (isUpcomingSoon) {
          output.add(AppNotification(
            id: 'cust_reminder_$id',
            title: 'Reminder: Upcoming Haircut ⏰',
            body: 'Don\'t forget your "$serviceName" with $staffName scheduled for $timeStr.',
            timestamp: now.subtract(const Duration(minutes: 10)),
            icon: Icons.alarm_rounded,
            color: Colors.amber[800] ?? Colors.orange,
            type: 'reminder',
            metadata: appt,
          ));
        }

        output.add(AppNotification(
          id: 'cust_confirmed_$id',
          title: 'Appointment Confirmed! ✂️',
          body: 'Your appointment for "$serviceName" with $staffName on $timeStr is confirmed.',
          timestamp: startTime.isAfter(now) ? now.subtract(const Duration(hours: 1)) : startTime,
          icon: Icons.verified_rounded,
          color: const Color(0xFF1E88E5),
          type: 'booking',
          metadata: appt,
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STAFF / BARBER NOTIFICATIONS GENERATION
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _generateStaffNotifications(
      List<AppNotification> output, String staffId) async {
    final now = DateTime.now();

    List<Map<String, dynamic>> appointments = [];
    try {
      final res = await SupabaseConfig.client
          .from(SupabaseConfig.appointmentDetailsView)
          .select()
          .eq('staff_id', staffId)
          .order('start_time', ascending: false)
          .limit(15);
      appointments = SupabaseServiceHelpers.asMapList(res);
    } catch (e) {
      debugPrint('Error loading barber appointments for notifications: $e');
    }

    for (final appt in appointments) {
      final id = (appt['appointment_id'] ?? appt['id'] ?? '').toString();
      final customerName = appt['customer_name']?.toString() ?? 'A client';
      final serviceName = appt['service_name']?.toString() ?? 'Service';
      final status = (appt['status']?.toString() ?? 'booked').toLowerCase();
      final startTime = SupabaseServiceHelpers.parseDateTime(appt['start_time']) ?? now;
      final timeStr = _formatFriendlyDateTime(startTime);

      if (status != 'canceled') {
        output.add(AppNotification(
          id: 'barber_appt_$id',
          title: 'Client Scheduled: $customerName 💈',
          body: '$customerName is booked for "$serviceName" on $timeStr.',
          timestamp: startTime.isAfter(now) ? now.subtract(const Duration(minutes: 20)) : startTime,
          icon: Icons.event_available_rounded,
          color: const Color(0xFF1E88E5),
          type: 'booking',
          metadata: appt,
        ));
      }
    }
  }

  static String _formatFriendlyDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isTomorrow = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day + 1;

    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $ampm';

    if (isToday) return 'Today at $timeStr';
    if (isTomorrow) return 'Tomorrow at $timeStr';
    return '${dt.month}/${dt.day}/${dt.year} at $timeStr';
  }
}
