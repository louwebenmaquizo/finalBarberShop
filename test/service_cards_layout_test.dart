import 'dart:convert';

import 'package:barber/screens/customer/customer_catalog_screen.dart';
import 'package:barber/screens/customer/customer_home_screen.dart';
import 'package:barber/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Renders the customer Home and Catalog screens with real-looking catalog
/// data (served by a fake backend) and fails if a service card overflows,
/// e.g. the price or "Book Now" button being cut off.
void main() {
  final services = [
    for (final (i, s) in const [
      [
        'Skin Fade',
        'Haircut',
        'A precise skin fade with a blended finish.',
        1250
      ],
      [
        'Kids Haircut',
        'Haircut',
        'A comfortable haircut service for children.',
        150
      ],
      [
        'Haircut and Beard',
        'Haircut',
        'A complete haircut and beard-grooming package.',
        32
      ],
      [
        'Hair Styling',
        'Styling',
        'Wash, dry, and style for a polished finish.',
        18
      ],
    ].indexed)
      {
        'service_id': '00000000-0000-4000-8000-00000000000$i',
        'name': s[0],
        'category_name': s[1],
        'description': s[2],
        'price': s[3],
        'duration_minutes': 30,
        'is_active': true,
        'image_url': null,
      },
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(
      url: 'http://fake.supabase.test',
      publishableKey: 'sb_publishable_test',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        final body =
            path.contains('service_catalog') ? jsonEncode(services) : '[]';
        return http.Response(body, 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });

  const customer = <String, dynamic>{
    'user_id': '00000000-0000-4000-8000-000000000001',
    'customer_id': '00000000-0000-4000-8000-000000000002',
    'full_name': 'Juan Dela Cruz',
    'phone': '639171234567',
    'role': 'customer',
  };

  final screens = <String, Widget Function()>{
    'Home': () => const CustomerHomeScreen(userData: customer),
    'Catalog': () => const CustomerCatalogScreen(userData: customer),
  };
  const sizes = {
    '320x568': Size(320, 568),
    '360x780': Size(360, 780),
    '412x915': Size(412, 915),
  };

  for (final screen in screens.entries) {
    for (final size in sizes.entries) {
      for (final textScale in const [1.0, 1.15, 1.3]) {
        testWidgets(
            '${screen.key} service cards fit on ${size.key}, text x$textScale',
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
          };

          tester.view.physicalSize = size.value * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(MediaQuery(
            data: MediaQueryData(
              size: size.value,
              devicePixelRatio: 3,
              textScaler: TextScaler.linear(textScale),
            ),
            child:
                MaterialApp(theme: AppTheme.lightTheme, home: screen.value()),
          ));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 300));
          }
          final bookButtons =
              find.text('Book Now', skipOffstage: false).evaluate().length;
          // Bring every card into view so all of them are laid out.
          final scrollables = find.byType(Scrollable);
          if (scrollables.evaluate().isNotEmpty) {
            await tester.drag(scrollables.first, const Offset(0, -2000));
            await tester.pump(const Duration(milliseconds: 300));
          }

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          FlutterError.onError = previous;

          expect(bookButtons, greaterThan(0),
              reason: 'service cards should be shown');
          expect(overflows.toSet().toList(), isEmpty);
        }, timeout: const Timeout(Duration(seconds: 60)));
      }
    }
  }
}
