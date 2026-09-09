import 'api_service.dart';
import '../config/api_config.dart';
import 'supabase_service_helpers.dart';

class BookingService {
  BookingService._();

  static Future<List<Map<String, dynamic>>> getAllBookings() async {
    final appointments = await ApiService.getAppointments();
    final seenIds = <String>{};
    final uniqueList = <Map<String, dynamic>>[];

    for (final value in appointments) {
      final booking = Map<String, dynamic>.from(value as Map);
      final id = (booking['appointment_id'] ?? booking['id'] ?? '').toString();
      if (id.isNotEmpty && seenIds.contains(id)) {
        continue;
      }
      if (id.isNotEmpty) seenIds.add(id);

      uniqueList.add(<String, dynamic>{
        ...booking,
        'appointment_id': id,
        'customer_id': booking['customer_id'] ?? '',
        'customer_name': booking['customer_name'] ?? 'Unknown',
        'customer_phone': booking['customer_phone'] ?? '',
        'customer_photo': booking['customer_photo'],
        'staff_id': booking['staff_id'] ?? '',
        'date': booking['date'] ?? '',
        'time': booking['time'] ?? '',
        'start_time': booking['start_time'],
        'end_time': booking['end_time'],
        'status': booking['status'] ?? 'booked',
        'service_id': booking['service_id'] ?? '',
        'service_name': booking['service_name'] ?? '',
        'service_price': booking['service_price'] ?? booking['price'] ?? 0,
        'service_image': booking['service_image'] ?? booking['image_url'],
        'staff_name': booking['staff_name'] ?? '',
        'notes': booking['notes'] ?? '',
      });
    }

    return uniqueList;
  }

  /// Fetches all active booked intervals for a specific barber on a specific date.
  /// Used to visually disable conflicting time slots and prevent double bookings.
  static Future<List<Map<String, dynamic>>> getStaffBookedIntervals({
    required String staffId,
    required DateTime date,
    String? excludeAppointmentId,
  }) async {
    if (staffId.isEmpty) return [];

    try {
      final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      final startIso = SupabaseServiceHelpers.toUtcIso(startOfDay.toIso8601String());
      final endIso = SupabaseServiceHelpers.toUtcIso(endOfDay.toIso8601String());

      final data = await SupabaseConfig.client
          .from(SupabaseConfig.appointmentsTable)
          .select('id, staff_id, start_time, end_time, status')
          .eq('staff_id', staffId)
          .gte('end_time', startIso)
          .lte('start_time', endIso)
          .not('status', 'in', '("canceled","declined","no-show")');

      final rows = SupabaseServiceHelpers.asMapList(data);
      final intervals = <Map<String, dynamic>>[];

      for (final row in rows) {
        final id = (row['id'] ?? '').toString();
        if (excludeAppointmentId != null && id == excludeAppointmentId) {
          continue;
        }

        final rawStart = row['start_time'];
        final rawEnd = row['end_time'];
        if (rawStart == null || rawEnd == null) continue;

        final startDt = DateTime.tryParse(rawStart.toString())?.toLocal();
        final endDt = DateTime.tryParse(rawEnd.toString())?.toLocal();

        if (startDt != null && endDt != null) {
          intervals.add({
            'appointment_id': id,
            'start': startDt,
            'end': endDt,
            'start_formatted': _formatTime(startDt),
            'end_formatted': _formatTime(endDt),
          });
        }
      }

      return intervals;
    } catch (_) {
      return [];
    }
  }

  /// Checks whether a proposed appointment interval [start, end] conflicts with any existing intervals.
  /// Returns the conflicting interval Map if there is a conflict, or null if free.
  static Map<String, dynamic>? findConflictingBooking({
    required DateTime proposedStart,
    required DateTime proposedEnd,
    required List<Map<String, dynamic>> existingIntervals,
  }) {
    for (final interval in existingIntervals) {
      final bookedStart = interval['start'] as DateTime?;
      final bookedEnd = interval['end'] as DateTime?;
      if (bookedStart == null || bookedEnd == null) continue;

      // Overlap formula: proposedStart < bookedEnd && proposedEnd > bookedStart
      if (proposedStart.isBefore(bookedEnd) && proposedEnd.isAfter(bookedStart)) {
        return interval;
      }
    }
    return null;
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  static Future<List<Map<String, dynamic>>> searchBookings(String query) async {
    final bookings = await getAllBookings();
    if (query.trim().isEmpty) return bookings;
    final needle = query.toLowerCase();
    return bookings.where((booking) {
      return const [
        'customer_name',
        'service_name',
        'staff_name',
        'date',
        'time',
      ].any(
        (field) =>
            (booking[field] ?? '').toString().toLowerCase().contains(needle),
      );
    }).toList();
  }

  static Future<Map<String, dynamic>?> getBookingById(
    String appointmentId,
  ) async {
    final booking = await ApiService.getAppointmentById(appointmentId);
    if (booking == null) return null;
    return {
      'appointment_id': booking['appointment_id'] ?? '',
      'customer_id': booking['customer_id'] ?? '',
      'customer_name': booking['customer_name'] ?? 'Unknown',
      'staff_id': booking['staff_id'] ?? '',
      'staff_name': booking['staff_name'] ?? '',
      'service_id': booking['service_id'] ?? '',
      'service_name': booking['service_name'] ?? '',
      'service_price': booking['service_price'] ?? booking['price'] ?? 0.0,
      'date': booking['date'] ?? booking['start_time'] ?? '',
      'time': booking['time'] ?? '',
      'start_time': booking['start_time'],
      'end_time': booking['end_time'],
      'notes': booking['notes'] ?? '',
      'status': booking['status'] ?? 'booked',
    };
  }

  static Future<Map<String, dynamic>> updateBooking(
    String appointmentId,
    Map<String, dynamic> bookingData,
  ) =>
      ApiService.updateAppointment(appointmentId, bookingData);

  static Future<Map<String, dynamic>> deleteBooking(
    String appointmentId,
  ) =>
      ApiService.updateAppointment(
        appointmentId,
        {'status': 'canceled'},
      );

  static Future<Map<String, dynamic>> cancelBooking(
    String appointmentId,
  ) =>
      deleteBooking(appointmentId);

  static Future<Map<String, dynamic>> rescheduleBooking(
    String appointmentId,
    String date,
    String time,
    String staffId,
  ) =>
      ApiService.updateAppointment(
        appointmentId,
        {
          'date': date,
          'time': time,
          'staff_id': staffId,
        },
      );

  /// The payment flow calls [TransactionService.createTransaction] first; that
  /// method uses the atomic `complete_appointment` RPC. This update is therefore
  /// intentionally idempotent and also supports barber-only completion flows.
  static Future<Map<String, dynamic>> completeBooking(
    String appointmentId,
  ) =>
      ApiService.updateAppointment(
        appointmentId,
        {'status': 'completed'},
      );
}
