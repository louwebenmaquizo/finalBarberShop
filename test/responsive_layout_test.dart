import 'package:barber/screens/admin/admin_home_screen.dart';
import 'package:barber/screens/ai_chat_screen.dart';
import 'package:barber/screens/auth/complete_profile_screen.dart';
import 'package:barber/screens/auth/login_screen.dart';
import 'package:barber/screens/auth/register_screen.dart';
import 'package:barber/screens/barber/barber_home_screen.dart';
import 'package:barber/screens/customer/customer_navigation_screen.dart';
import 'package:barber/screens/onboarding.dart';
import 'package:barber/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Renders the main screens at common phone sizes (and with enlarged system
/// text) and fails if any layout overflows. Uses the bundled Manrope font so
/// text has real widths. The backend is unreachable in tests, so screens are
/// checked in their loading/empty/error states.
void main() {
  const sizes = <String, Size>{
    'small phone 320x568': Size(320, 568),
    'phone 360x640': Size(360, 640),
    'large phone 412x915': Size(412, 915),
  };

  final customer = <String, dynamic>{
    'user_id': '00000000-0000-4000-8000-000000000001',
    'customer_id': '00000000-0000-4000-8000-000000000002',
    'username': 'juan',
    'full_name': 'Juan Dela Cruz',
    'email': 'juan@example.com',
    'phone': '639171234567',
    'role': 'customer',
    'is_profile_completed': true,
  };
  final barber = <String, dynamic>{
    'user_id': '00000000-0000-4000-8000-000000000003',
    'staff_id': '00000000-0000-4000-8000-000000000004',
    'name': 'Archie Boiser',
    'username': 'archie',
    'role': 'barber',
    'staff_role': 'Barber',
  };

  final screens = <String, Widget Function()>{
    'Onboarding': () => const OnboardingScreen(),
    'Login': () => const LoginScreen(),
    'Register': () => const RegisterScreen(),
    'Complete profile': () => CompleteProfileScreen(userData: customer),
    'Customer home': () => CustomerNavigationScreen(userData: customer),
    'Admin home': () => const AdminHomeScreen(username: 'admin'),
    'Barber home': () => BarberHomeScreen(barberData: barber),
    'AI chat': () => const AiChatScreen(),
  };

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(
      url: 'http://localhost:9',
      publishableKey: 'sb_publishable_test',
    );
  });

  for (final screen in screens.entries) {
    for (final size in sizes.entries) {
      for (final textScale in const [1.0, 1.3]) {
        testWidgets('${screen.key} fits on ${size.key}, text x$textScale',
            (tester) async {
          final overflows = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            final text = details.exceptionAsString();
            if (text.contains('overflowed')) {
              final where = RegExp(r'lib/[\w/]+\.dart:\d+')
                  .firstMatch(details.toString())
                  ?.group(0);
              overflows.add('${text.split('\n').first} at ${where ?? '?'}');
            }
            // Font loading and unreachable-backend errors are expected here.
          };

          tester.view.physicalSize = size.value * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: size.value,
                devicePixelRatio: 3,
                textScaler: TextScaler.linear(textScale),
              ),
              child: MaterialApp(theme: AppTheme.lightTheme, home: screen.value()),
            ),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 500));
          }

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));

          // Must be restored before expect() or the test framework asserts.
          FlutterError.onError = previous;
          expect(overflows.toSet().toList(), isEmpty);
        }, timeout: const Timeout(Duration(seconds: 60)));
      }
    }
  }
}
