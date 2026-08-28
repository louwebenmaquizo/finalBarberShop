import '../config/api_config.dart';
import 'api_service.dart' show ApiServiceExtension;

/// Booking Service
/// Contains all functions for booking/appointment-related operations
class BookingService {
  /// Get all appointments for the booking screen
  /// Returns a list of appointments with customer name, date, time, etc.
  static Future<List<Map<String, dynamic>>> getAllBookings() async {
    try {
      final response = await ApiServiceExtension.get(ApiConfig.appointmentsUrl);
      
      if (response['success'] == true && response['data'] != null) {
        final bookings = (response['data'] as List).map((booking) {
          return {
            'appointment_id': booking['appointment_id'] ?? '',
            'customer_name': booking['customer_name'] ?? 'Unknown',
            'date': booking['date'] ?? '',
            'time': booking['time'] ?? '',
            'status': booking['status'] ?? 'booked',
            'service_name': booking['service_name'] ?? '',
            'staff_name': booking['staff_name'] ?? '',
          };
        }).toList();
        return bookings;
      }
      return [];
    } catch (e) {
      print('Error fetching bookings: $e');
      return [];
    }
  }
  
  /// Search bookings by customer name, service, or staff
  /// Used for filtering in the booking screen
  static Future<List<Map<String, dynamic>>> searchBookings(String query) async {
    final allBookings = await getAllBookings();
    if (query.isEmpty) {
      return allBookings;
    }
    
    final searchQuery = query.toLowerCase();
    return allBookings.where((booking) {
      final customerName = (booking['customer_name'] ?? '').toLowerCase();
      final serviceName = (booking['service_name'] ?? '').toLowerCase();
      final staffName = (booking['staff_name'] ?? '').toLowerCase();
      final date = (booking['date'] ?? '').toLowerCase();
      final time = (booking['time'] ?? '').toLowerCase();
      
      return customerName.contains(searchQuery) || 
             serviceName.contains(searchQuery) || 
             staffName.contains(searchQuery) ||
             date.contains(searchQuery) ||
             time.contains(searchQuery);
    }).toList();
  }
  
  /// Get appointment by ID
  /// Returns full appointment details including IDs and price
  static Future<Map<String, dynamic>?> getBookingById(String appointmentId) async {
    try {
      final response = await ApiServiceExtension.get('${ApiConfig.appointmentsUrl}?appointment_id=$appointmentId');
      
      if (response['success'] == true && response['data'] != null) {
        final booking = response['data'];
        
        // Handle both single object and list
        Map<String, dynamic> bookingData;
        if (booking is List && booking.isNotEmpty) {
          bookingData = booking[0] as Map<String, dynamic>;
        } else if (booking is Map<String, dynamic>) {
          bookingData = booking;
        } else {
          return null;
        }
        
        return {
          'appointment_id': bookingData['appointment_id'] ?? '',
          'customer_id': bookingData['customer_id'] ?? '',
          'customer_name': bookingData['customer_name'] ?? 'Unknown',
          'staff_id': bookingData['staff_id'] ?? '',
          'staff_name': bookingData['staff_name'] ?? '',
          'service_id': bookingData['service_id'] ?? '',
          'service_name': bookingData['service_name'] ?? '',
          'service_price': bookingData['service_price'] ?? bookingData['price'] ?? 0.0,
          'date': bookingData['date'] ?? bookingData['start_time'] ?? '',
          'time': bookingData['time'] ?? '',
          'status': bookingData['status'] ?? 'booked',
        };
      }
      return null;
    } catch (e) {
      print('Error fetching booking by ID: $e');
      return null;
    }
  }
  
  /// Update appointment status
  /// For reschedule/delete functionality
  static Future<Map<String, dynamic>> updateBooking(String appointmentId, Map<String, dynamic> bookingData) async {
    try {
      bookingData['appointment_id'] = appointmentId;
      final response = await ApiServiceExtension.put(
        ApiConfig.appointmentsUrl,
        bookingData,
      );
      
      return response;
    } catch (e) {
      print('Error updating booking: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
  
  /// Delete appointment (set status to 'canceled')
  /// For delete functionality
  static Future<Map<String, dynamic>> deleteBooking(String appointmentId) async {
    try {
      final response = await ApiServiceExtension.put(
        ApiConfig.appointmentsUrl,
        {
          'appointment_id': appointmentId,
          'status': 'canceled',
        },
      );
      
      return response;
    } catch (e) {
      print('Error deleting booking: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Cancel appointment (alias for deleteBooking - sets status to 'canceled')
  /// For cancel functionality
  static Future<Map<String, dynamic>> cancelBooking(String appointmentId) async {
    return deleteBooking(appointmentId);
  }

  /// Reschedule appointment
  /// Updates appointment date, time, and staff_id
  static Future<Map<String, dynamic>> rescheduleBooking(
    String appointmentId,
    String date,
    String time,
    String staffId,
  ) async {
    try {
      final requestData = {
        'appointment_id': appointmentId,
        'date': date,  // Changed from appointment_date to date
        'time': time,   // Changed from appointment_time to time
        'staff_id': staffId,
      };
      
      print('Rescheduling booking with data: $requestData');
      
      final response = await ApiServiceExtension.put(
        ApiConfig.appointmentsUrl,
        requestData,
      );
      
      print('Reschedule response: $response');
      
      return response;
    } catch (e) {
      print('Error rescheduling booking: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Complete appointment
  /// Updates appointment status to 'completed'
  static Future<Map<String, dynamic>> completeBooking(String appointmentId) async {
    try {
      final response = await ApiServiceExtension.put(
        ApiConfig.appointmentsUrl,
        {
          'appointment_id': appointmentId,
          'status': 'completed',
        },
      );
      
      return response;
    } catch (e) {
      print('Error completing booking: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}

