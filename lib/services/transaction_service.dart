import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';
import 'supabase_service_helpers.dart';

class TransactionService {
  TransactionService._();

  static Future<Map<String, dynamic>> createTransaction({
    required String appointmentId,
    required String customerId,
    required double amount,
    required String paymentMethod,
    required String staffId,
    double tipAmount = 0.0,
    double taxAmount = 0.0,
  }) async {
    try {
      final data = await SupabaseConfig.client.rpc(
        SupabaseConfig.completeAppointmentRpc,
        params: {
          'p_appointment_id': appointmentId,
          'p_amount': amount,
          'p_payment_method': paymentMethod,
          'p_tip_amount': tipAmount,
          'p_tax_amount': taxAmount,
        },
      );
      return {
        'success': true,
        'message': 'Payment recorded and appointment completed.',
        'data': SupabaseServiceHelpers.asMap(data),
      };
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        final existing = await getTransactionByAppointmentId(appointmentId);
        if (existing != null) {
          return {
            'success': true,
            'message': 'This appointment was already completed.',
            'data': existing,
          };
        }
      }
      return SupabaseServiceHelpers.failure(error);
    } catch (error) {
      return SupabaseServiceHelpers.failure(error);
    }
  }

  static Future<List<Map<String, dynamic>>> getAllTransactions({
    String? customerId,
    String? staffId,
    String? startDate,
    String? endDate,
  }) async {
    try {
      dynamic query = SupabaseConfig.client
          .from(SupabaseConfig.transactionDetailsView)
          .select();
      if (customerId != null && customerId.isNotEmpty) {
        query = query.eq('customer_id', customerId);
      }
      if (staffId != null && staffId.isNotEmpty) {
        query = query.eq('staff_id', staffId);
      }
      final start = startDate == null ? null : DateTime.tryParse(startDate);
      if (start != null) {
        query = query.gte(
          'created_at',
          DateTime(start.year, start.month, start.day)
              .toUtc()
              .toIso8601String(),
        );
      }
      final end = endDate == null ? null : DateTime.tryParse(endDate);
      if (end != null) {
        query = query.lt(
          'created_at',
          DateTime(end.year, end.month, end.day)
              .add(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
        );
      }

      final data = await query.order('created_at', ascending: false);
      return SupabaseServiceHelpers.asMapList(data)
          .map(_normalizeTransaction)
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<Map<String, dynamic>?> getTransactionByAppointmentId(
    String appointmentId,
  ) async {
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.transactionDetailsView)
          .select()
          .eq('appointment_id', appointmentId)
          .maybeSingle();
      final transaction = SupabaseServiceHelpers.asMap(data);
      return transaction.isEmpty ? null : _normalizeTransaction(transaction);
    } catch (_) {
      return null;
    }
  }

  static Future<double> getTodayRevenue() async {
    final today = DateTime.now();
    final date = '${today.year}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final transactions = await getAllTransactions(
      startDate: date,
      endDate: date,
    );
    return transactions
        .where((transaction) => transaction['status'] == 'completed')
        .fold<double>(
          0,
          (total, transaction) =>
              total + SupabaseServiceHelpers.asDouble(transaction['amount']),
        );
  }

  static Map<String, dynamic> _normalizeTransaction(
    Map<String, dynamic> row,
  ) {
    final transaction = Map<String, dynamic>.from(row);
    transaction['transaction_id'] =
        transaction['transaction_id'] ?? transaction['id'];
    transaction['amount'] =
        SupabaseServiceHelpers.asDouble(transaction['amount']);
    transaction['tip_amount'] =
        SupabaseServiceHelpers.asDouble(transaction['tip_amount']);
    transaction['tax_amount'] =
        SupabaseServiceHelpers.asDouble(transaction['tax_amount']);
    return transaction;
  }
}
