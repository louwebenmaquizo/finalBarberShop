// API Configuration
class ApiConfig {
  // For browser/web (Edge, Chrome) & local server
  static const String baseUrl = 'http://localhost/barber_api';
  
  // For physical device connected via USB (with ADB port forwarding: adb reverse tcp:8080 tcp:80)
  // static const String baseUrl = 'http://127.0.0.1:8080/barber_api';
  
  // Alternative: For physical device on same WiFi network (without ADB)
  // static const String baseUrl = 'http://192.168.1.7/barber_api'; // Your computer's IP
  
  // For Android emulator
  // static const String baseUrl = 'http://10.0.2.2/barber_api';
  
  // API Endpoints
  static String get loginUrl => '$baseUrl/login.php';
  static String get registerUrl => '$baseUrl/register.php';
  static String get customersUrl => '$baseUrl/customers.php';
  static String get appointmentsUrl => '$baseUrl/appointments.php';
  static String get employeesUrl => '$baseUrl/employees.php';
  static String get servicesUrl => '$baseUrl/services.php';
  static String get categoriesUrl => '$baseUrl/categories.php';
  
  // Customer-specific endpoints
  static String customerAppointments(String customerId) => '$baseUrl/customers/$customerId/appointments.php';
  static String customerProfile(String customerId) => '$baseUrl/customers/$customerId/profile.php';
  
  // Feedback endpoint
  static String get feedbackUrl => '$baseUrl/feedback.php';
  
  // Transactions endpoint
  static String get transactionsUrl => '$baseUrl/transactions.php';
}

