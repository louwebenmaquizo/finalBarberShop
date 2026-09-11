import 'package:supabase_flutter/supabase_flutter.dart';

/// Central Supabase configuration.
///
/// Supply both values at build/run time:
///
/// ```text
/// --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co
/// --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
/// ```
///
/// A publishable key is safe to use in a client application when Row Level
/// Security is configured correctly. A service-role/secret key must never be
/// added to this project.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY');

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) {
      throw StateError(
        'Supabase is not configured. Run Flutter with '
        '--dart-define=SUPABASE_URL=... and '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=...',
      );
    }

    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static const String profilesTable = 'profiles';
  static const String customersTable = 'customers';
  static const String staffTable = 'staff';
  static const String categoriesTable = 'service_categories';
  static const String servicesTable = 'services';
  static const String appointmentsTable = 'appointments';
  static const String transactionsTable = 'transactions';
  static const String feedbackTable = 'feedback';

  static const String appointmentDetailsView = 'appointment_details';
  static const String serviceCatalogView = 'service_catalog';
  static const String staffDirectoryView = 'staff_directory';
  static const String categoryCatalogView = 'category_catalog';
  static const String transactionDetailsView = 'transaction_details';

  static const String createAppointmentRpc = 'create_appointment';
  static const String rescheduleAppointmentRpc = 'reschedule_appointment';
  static const String completeAppointmentRpc = 'complete_appointment';
  static const String setAppointmentStatusRpc = 'set_appointment_status';
  static const String cancelAppointmentRpc = 'cancel_appointment';
  static const String updateAppointmentNotesRpc = 'update_appointment_notes';
  static const String refundTransactionRpc = 'refund_transaction';
  static const String dashboardRpc = 'get_dashboard_data';

  static const String customerAvatarsBucket = 'customer-avatars';
  static const String staffAvatarsBucket = 'staff-avatars';
  static const String serviceImagesBucket = 'service-images';
}

/// Logical routes retained for widgets that still use [ApiServiceExtension].
/// They are dispatched to Supabase and are never requested over HTTP.
@Deprecated('Use SupabaseConfig and the domain services instead.')
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'supabase://barber';

  static String get loginUrl => '$baseUrl/login';
  static String get registerUrl => '$baseUrl/register';
  static String get customersUrl => '$baseUrl/customers';
  static String get appointmentsUrl => '$baseUrl/appointments';
  static String get employeesUrl => '$baseUrl/employees';
  static String get servicesUrl => '$baseUrl/services';
  static String get categoriesUrl => '$baseUrl/categories';
  static String get feedbackUrl => '$baseUrl/feedback';
  static String get transactionsUrl => '$baseUrl/transactions';

  static String customerAppointments(String customerId) =>
      '$baseUrl/customers/$customerId/appointments';

  static String customerProfile(String customerId) =>
      '$baseUrl/customers/$customerId/profile';
}
