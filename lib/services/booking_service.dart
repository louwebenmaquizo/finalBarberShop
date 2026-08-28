import 'api_service.dart';

class BookingService {
  BookingService._();

  static Future<List<Map<String, dynamic>>> getAllBookings() async {
    final appointments = await ApiService.getAppointments();
    return appointments.map((value) {
      final booking = Map<String, dynamic>.from(value as Map);
      return <String, dynamic>{
        ...booking,
        'appointment_id': booking['appointment_id'] ?? '',
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
      };
    }).toList();
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
