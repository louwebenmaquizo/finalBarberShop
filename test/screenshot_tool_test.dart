// Developer tool, not a regular test: renders the main screens in light and
// dark mode with sample data from a fake backend and saves PNG screenshots,
// so theme/layout changes can be reviewed visually.
//
//   flutter test test/screenshot_tool_test.dart \
//     --dart-define=SCREENSHOTS=1 --dart-define=SHOT_DIR=C:/path/to/output
//
// Skipped unless SCREENSHOTS=1 is passed.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:barber/screens/admin/booking_screen.dart';
import 'package:barber/screens/admin/catalog_screen.dart';
import 'package:barber/screens/admin/dashboard_screen.dart';
import 'package:barber/screens/admin/employee_screen.dart';
import 'package:barber/screens/admin/settings_screen.dart';
import 'package:barber/screens/ai_chat_screen.dart';
import 'package:barber/screens/auth/login_screen.dart';
import 'package:barber/screens/barber/barber_home_screen.dart';
import 'package:barber/screens/customer/customer_appointments_screen.dart';
import 'package:barber/screens/customer/customer_booking_screen.dart';
import 'package:barber/screens/customer/customer_catalog_screen.dart';
import 'package:barber/screens/customer/customer_home_screen.dart';
import 'package:barber/screens/customer/customer_settings_screen.dart';
import 'package:barber/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _enabled = String.fromEnvironment('SCREENSHOTS') == '1';
const _outDir = String.fromEnvironment('SHOT_DIR', defaultValue: 'build/screenshots');

final _now = DateTime.now();
String _iso(int dayOffset, int hour) =>
    DateTime(_now.year, _now.month, _now.day + dayOffset, hour).toUtc().toIso8601String();

final _services = [
  for (final (i, s) in const [
    ['Skin Fade', 'Haircut', 'A precise skin fade with a blended finish.', 250],
    ['Kids Haircut', 'Haircut', 'A comfortable haircut service for children.', 150],
    ['Haircut and Beard', 'Haircut', 'A complete haircut and beard-grooming package.', 350],
    ['Hair Styling', 'Styling', 'Wash, dry, and style for a polished finish.', 180],
  ].indexed)
    {
      'service_id': 's000000$i',
      'name': s[0],
      'category_name': s[1],
      'category_id': 'c-${s[1]}',
      'description': s[2],
      'price': s[3],
      'cost': 50,
      'duration_minutes': 30,
      'is_active': true,
      'image_url': null,
    },
];
final _categories = [
  {'category_id': 'c-Haircut', 'name': 'Haircut', 'description': 'Cuts', 'service_count': 3},
  {'category_id': 'c-Styling', 'name': 'Styling', 'description': 'Styling', 'service_count': 1},
];
final _staff = [
  {'staff_id': 'st1', 'name': 'Marco Reyes', 'role': 'Senior Barber', 'skills': 'Fades, beard', 'is_active': true, 'phone': '09171234567', 'email': 'marco@shop.ph'},
  {'staff_id': 'st2', 'name': 'Jun Santos', 'role': 'Barber', 'skills': 'Classic cuts', 'is_active': true, 'phone': '09179876543', 'email': 'jun@shop.ph'},
];
final _appointments = [
  for (final (i, a) in const [
    ['pending', 0, 15, 'Ana Cruz', 'Skin Fade', 'Marco Reyes'],
    ['booked', 1, 10, 'Ben Lim', 'Kids Haircut', 'Jun Santos'],
    ['in_progress', 0, 9, 'Carlo Tan', 'Haircut and Beard', 'Marco Reyes'],
    ['completed', -1, 11, 'Dina Ramos', 'Hair Styling', 'Jun Santos'],
  ].indexed)
    {
      'appointment_id': 'a000000$i',
      'customer_id': 'cust1',
      'staff_id': a[5] == 'Marco Reyes' ? 'st1' : 'st2',
      'service_id': 's0000000',
      'start_time': _iso(a[1] as int, a[2] as int),
      'end_time': _iso(a[1] as int, (a[2] as int) + 1),
      'status': a[0],
      'customer_name': a[3],
      'customer_phone': '09170000000',
      'service_name': a[4],
      'staff_name': a[5],
      'service_price': 250,
      'duration_minutes': 30,
      'notes': '',
    },
];
final _dashboard = {
  'stats': {'today_bookings': 3, 'total_bookings': 42, 'total_barbers': 2, 'revenue_today': 1250, 'pending_count': 1},
  'analytics': {'days': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], 'values': [2, 4, 3, 5, 1, 6, 3]},
  'next_client': {'customer_name': 'Ana Cruz', 'date': 'October 25, 2026', 'time': '3:00 PM', 'end_time': '3:30 PM', 'service': 'Skin Fade', 'employee': 'Marco Reyes', 'status': 'booked'},
  'recent_bookings': [
    {'appointment_id': 'a0000000', 'time': '3:00 PM', 'date_label': 'Oct 25, 2026', 'customer': 'Ana Cruz', 'service': 'Skin Fade', 'price': 250, 'schedule': '3:00 PM - 3:30 PM', 'employee': 'Marco Reyes', 'status': 'pending', 'date': _iso(0, 15)},
  ],
  'top_barbers': [
    {'staff_id': 'st1', 'name': 'Marco Reyes', 'role': 'Senior Barber', 'total_appointments': 30},
  ],
  'monthly_revenue': [
    {'month': 'Sep', 'revenue': 8000},
    {'month': 'Oct', 'revenue': 12500},
  ],
};

Object _bodyFor(String path) {
  if (path.endsWith('/rpc/get_dashboard_data')) return _dashboard;
  if (path.contains('service_catalog') || path.endsWith('/services')) return _services;
  if (path.contains('category_catalog') || path.contains('service_categories')) return _categories;
  if (path.contains('staff_directory') || path.endsWith('/staff')) return _staff;
  if (path.contains('appointment_details')) return _appointments;
  if (path.contains('/customers')) {
    return [
      {'id': 'cust1', 'customer_id': 'cust1', 'user_id': 'u1', 'full_name': 'Juan Dela Cruz', 'phone': '639171234567', 'email': 'juan@example.com'},
    ];
  }
  return [];
}

Future<void> _loadIconFont() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter_windows_3.41.4-stable/flutter';
  final file = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!file.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  await loader.load();
}

void main() {
  const customer = <String, dynamic>{
    'user_id': 'u1',
    'customer_id': 'cust1',
    'full_name': 'Juan Dela Cruz',
    'username': 'juan',
    'email': 'juan@example.com',
    'phone': '639171234567',
    'role': 'customer',
    'is_profile_completed': true,
  };
  const barber = <String, dynamic>{
    'user_id': 'u2',
    'staff_id': 'st1',
    'name': 'Marco Reyes',
    'full_name': 'Marco Reyes',
    'username': 'marco',
    'role': 'barber',
  };

  final screens = <String, Widget Function()>{
    'admin_dashboard': () => const Scaffold(body: DashboardScreen()),
    'admin_employee': () => const Scaffold(body: EmployeeScreen()),
    'admin_catalog': () => const Scaffold(body: CatalogScreen()),
    'admin_booking': () => const Scaffold(body: BookingScreen()),
    'admin_settings': () => const Scaffold(body: SettingsScreen()),
    'barber_home': () => const BarberHomeScreen(barberData: barber),
    'customer_home': () => const Scaffold(body: CustomerHomeScreen(userData: customer)),
    'customer_catalog': () => const CustomerCatalogScreen(userData: customer),
    'customer_booking': () => const CustomerBookingScreen(userData: customer),
    'customer_appointments': () => const CustomerAppointmentsScreen(userData: customer),
    'customer_settings': () => const CustomerSettingsScreen(userData: customer),
    'ai_chat': () => const AiChatScreen(),
    'login': () => const LoginScreen(),
  };

  setUpAll(() async {
    if (!_enabled) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadIconFont();
    await Supabase.initialize(
      url: 'http://fake.supabase.test',
      publishableKey: 'sb_publishable_test',
      httpClient: MockClient((request) async => http.Response(
            jsonEncode(_bodyFor(request.url.path)),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          )),
    );
    Directory(_outDir).createSync(recursive: true);
  });

  for (final screen in screens.entries) {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('screenshot ${screen.key} ${mode.name}', (tester) async {
        final previous = FlutterError.onError;
        FlutterError.onError = (_) {};
        tester.view.physicalSize = const Size(412, 915) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        ThemeService.themeModeNotifier.value = mode;

        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: screen.value(),
          ),
        ));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.runAsync(() async {
          for (final element in find.byType(Image).evaluate()) {
            final widget = element.widget as Image;
            await precacheImage(widget.image, element);
          }
        });
        await tester.pump();

        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$_outDir/${screen.key}_${mode.name}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        ThemeService.themeModeNotifier.value = ThemeMode.light;
        FlutterError.onError = previous;
      }, skip: !_enabled, timeout: const Timeout(Duration(seconds: 90)));
    }
  }
}
