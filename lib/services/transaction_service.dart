import '../config/api_config.dart';
import 'api_service.dart' show ApiServiceExtension;

/// Transaction Service
/// Contains all functions for transaction/payment-related operations
class TransactionService {
  /// Create a new transaction when an appointment is completed
  /// Required: appointment_id, customer_id, amount, payment_method, staff_id
  /// Optional: tip_amount, tax_amount
  static Future<Map<String, dynamic>> createTransaction({
    required String appointmentId,
    required String customerId,
    required double amount,
    required String paymentMethod, // 'cash', 'card', 'mobile'
    required String staffId,
    double tipAmount = 0.0,
    double taxAmount = 0.0,
  }) async {
    try {
      final transactionData = {
        'appointment_id': appointmentId,
        'customer_id': customerId,
        'amount': amount.toStringAsFixed(2),
        'payment_method': paymentMethod,
        'staff_id': staffId,
        'tip_amount': tipAmount.toStringAsFixed(2),
        'tax_amount': taxAmount.toStringAsFixed(2),
        'status': 'completed',
      };

      final response = await ApiServiceExtension.post(
        ApiConfig.transactionsUrl,
        transactionData,
      );

      return response;
    } catch (e) {
      print('Error creating transaction: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Get all transactions
  /// Optional filters: customer_id, staff_id, date range
  static Future<List<Map<String, dynamic>>> getAllTransactions({
    String? customerId,
    String? staffId,
    String? startDate,
    String? endDate,
  }) async {
    try {
      String url = ApiConfig.transactionsUrl;
      final queryParams = <String>[];

      if (customerId != null) {
        queryParams.add('customer_id=$customerId');
      }
      if (staffId != null) {
        queryParams.add('staff_id=$staffId');
      }
      if (startDate != null) {
        queryParams.add('start_date=$startDate');
      }
      if (endDate != null) {
        queryParams.add('end_date=$endDate');
      }

      if (queryParams.isNotEmpty) {
        url += '?${queryParams.join('&')}';
      }

      final response = await ApiServiceExtension.get(url);

      if (response['success'] == true && response['data'] != null) {
        final transactions = (response['data'] as List).map((transaction) {
          return {
            'transaction_id': transaction['transaction_id'] ?? '',
            'appointment_id': transaction['appointment_id'] ?? '',
            'customer_id': transaction['customer_id'] ?? '',
            'customer_name': transaction['customer_name'] ?? '',
            'amount': transaction['amount'] ?? 0.0,
            'payment_method': transaction['payment_method'] ?? '',
            'tip_amount': transaction['tip_amount'] ?? 0.0,
            'tax_amount': transaction['tax_amount'] ?? 0.0,
            'staff_id': transaction['staff_id'] ?? '',
            'staff_name': transaction['staff_name'] ?? '',
            'status': transaction['status'] ?? 'completed',
            'created_at': transaction['created_at'] ?? '',
          };
        }).toList();
        return transactions;
      }
      return [];
    } catch (e) {
      print('Error fetching transactions: $e');
      return [];
    }
  }

  /// Get transaction by appointment ID
  static Future<Map<String, dynamic>?> getTransactionByAppointmentId(String appointmentId) async {
    try {
      final response = await ApiServiceExtension.get(
        '${ApiConfig.transactionsUrl}?appointment_id=$appointmentId',
      );

      if (response['success'] == true && response['data'] != null) {
        final transaction = response['data'] as Map<String, dynamic>;
        return transaction;
      }
      return null;
    } catch (e) {
      print('Error fetching transaction by appointment ID: $e');
      return null;
    }
  }

  /// Get today's revenue
  /// Used for dashboard statistics
  static Future<double> getTodayRevenue() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final transactions = await getAllTransactions(
        startDate: today,
        endDate: today,
      );

      double totalRevenue = 0.0;
      for (var transaction in transactions) {
        if (transaction['status'] == 'completed') {
          final amount = transaction['amount'];
          if (amount is double) {
            totalRevenue += amount;
          } else if (amount is String) {
            totalRevenue += double.tryParse(amount) ?? 0.0;
          } else if (amount is int) {
            totalRevenue += amount.toDouble();
          }
        }
      }

      return totalRevenue;
    } catch (e) {
      print('Error calculating today revenue: $e');
      return 0.0;
    }
  }
}

