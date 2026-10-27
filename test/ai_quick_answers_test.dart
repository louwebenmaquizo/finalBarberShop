import 'dart:convert';

import 'package:barber/config/shop_info.dart';
import 'package:barber/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The chat's suggested questions are answered from data, not by the AI.
/// These tests check the answers are exactly right for known data.
void main() {
  final now = DateTime.now();
  String today(int hour) =>
      DateTime(now.year, now.month, now.day, hour).toUtc().toIso8601String();

  final services = [
    {'name': 'Skin Fade', 'price': 120000, 'duration_minutes': 45, 'category_name': 'Haircut', 'is_active': true},
    {'name': 'Kids Haircut', 'price': 80000, 'duration_minutes': 30, 'category_name': 'Haircut', 'is_active': true},
    {'name': 'Beard Trim', 'price': 60000, 'duration_minutes': 20, 'category_name': 'Beard', 'is_active': true},
    {'name': 'Hair Spa', 'price': 150000, 'duration_minutes': 60, 'category_name': 'Styling', 'is_active': true},
    {'name': 'Old Promo', 'price': 10000, 'duration_minutes': 10, 'category_name': 'Haircut', 'is_active': false},
  ];
  final staff = [
    {'name': 'Marco Reyes', 'role': 'Senior Barber', 'skills': 'Skin fades, beard', 'is_active': true},
    {'name': 'Jun Santos', 'role': 'Barber', 'skills': 'Classic cuts', 'is_active': true},
    {'name': 'Owner Account', 'role': 'Admin', 'skills': '', 'is_active': true},
    {'name': 'Left Shop', 'role': 'Barber', 'skills': 'Fades', 'is_active': false},
  ];
  final appointments = [
    {'start_time': today(9), 'status': 'completed', 'customer_name': 'An', 'service_name': 'Skin Fade', 'staff_name': 'Marco Reyes'},
    {'start_time': today(10), 'status': 'booked', 'customer_name': 'Binh', 'service_name': 'Beard Trim', 'staff_name': 'Jun Santos'},
    {'start_time': today(11), 'status': 'canceled', 'customer_name': 'Chi', 'service_name': 'Kids Haircut', 'staff_name': 'Jun Santos'},
    {'start_time': today(23), 'status': 'pending', 'customer_name': 'Dung', 'service_name': 'Hair Spa', 'staff_name': 'Marco Reyes'},
  ];
  final transactions = [
    {'amount': 100000, 'tip_amount': 20000, 'payment_method': 'cash', 'status': 'completed'},
    {'amount': 80000, 'tip_amount': 0, 'payment_method': 'card', 'status': 'completed'},
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fake.supabase.test',
      publishableKey: 'sb_publishable_test',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        final status = request.url.queryParameters['status'];
        Object body = [];
        if (path.contains('service_catalog')) body = services;
        if (path.contains('staff_directory')) body = staff;
        if (path.contains('transaction_details')) body = transactions;
        if (path.contains('appointment_details')) {
          body = status == 'eq.pending'
              ? appointments.where((a) => a['status'] == 'pending').toList()
              : appointments;
        }
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });

  Future<String?> ask(String q, String role) => AiService.quickAnswer(q, userRole: role);

  group('ShopInfo VND', () {
    test('formats Vietnamese Dong', () {
      expect(ShopInfo.formatPrice(80000), '80.000 ₫');
      expect(ShopInfo.formatPrice(1250000), '1.250.000 ₫');
      expect(ShopInfo.formatPrice(0), '0 ₫');
      expect(ShopInfo.formatPrice('95000.00'), '95.000 ₫');
    });
    test('parses typed prices', () {
      expect(ShopInfo.parsePrice('80000'), 80000);
      expect(ShopInfo.parsePrice('80.000'), 80000);
      expect(ShopInfo.parsePrice('80,000'), 80000);
      expect(ShopInfo.parsePrice('1.250.000'), 1250000);
      expect(ShopInfo.parsePrice('80k'), 80000);
      expect(ShopInfo.parsePrice(''), isNull);
    });
  });

  group('customer suggested questions', () {
    test('every suggestion has an exact answer', () async {
      for (final q in AiService.customerQuickQuestions) {
        expect(await ask(q, 'customer'), isNotNull, reason: q);
      }
    });

    test('barbers: active barbers only, no admin accounts', () async {
      final a = (await ask('💈  Who are the barbers?', 'customer'))!;
      expect(a, contains('Marco Reyes'));
      expect(a, contains('Jun Santos'));
      expect(a, isNot(contains('Owner Account')));
      expect(a, isNot(contains('Left Shop')));
      expect(a, contains('(2)'));
    });

    test('services: active only, with VND prices', () async {
      final a = (await ask('What services are available?', 'customer'))!;
      expect(a, contains('Skin Fade** — 120.000 ₫, 45 min'));
      expect(a, isNot(contains('Old Promo')));
      expect(a, contains('(4)'));
    });

    test('cheapest: the three lowest active prices in order', () async {
      final a = (await ask('What are the cheapest services?', 'customer'))!;
      final beard = a.indexOf('Beard Trim'), kids = a.indexOf('Kids Haircut'), fade = a.indexOf('Skin Fade');
      expect([beard, kids, fade].every((i) => i >= 0), isTrue);
      expect(beard < kids && kids < fade, isTrue);
      expect(a, isNot(contains('Hair Spa')));
      expect(a, isNot(contains('Old Promo')));
    });

    test('durations: sorted shortest first', () async {
      final a = (await ask('How long does each service take?', 'customer'))!;
      expect(a.indexOf('Beard Trim** — 20 min') < a.indexOf('Hair Spa** — 60 min'), isTrue);
    });

    test('fades: only barbers who list fades', () async {
      final a = (await ask('Which barber is best for fades?', 'customer'))!;
      expect(a, contains('Marco Reyes'));
      expect(a, isNot(contains('Jun Santos')));
      expect(a, isNot(contains('Left Shop')));
    });

    test('booking hours match the app rules', () async {
      final a = (await ask('What are your booking hours?', 'customer'))!;
      expect(a, contains(ShopInfo.bookingHoursLabel));
      expect(a, contains('${ShopInfo.maxDaysAhead} days'));
    });

    test('admin-only questions are not answered for customers', () async {
      expect(await ask("Today's revenue", 'customer'), isNull);
      expect(await ask('Add Barber', 'customer'), isNull);
    });

    test('free-form questions still go to the AI', () async {
      expect(await ask('I have curly hair, what should I get?', 'customer'), isNull);
    });
  });

  group('admin suggested questions', () {
    test('every suggestion has an exact answer', () async {
      for (final q in AiService.adminQuickQuestions) {
        expect(await ask(q, 'admin'), isNotNull, reason: q);
      }
    });

    test("today's bookings excludes canceled ones from the count", () async {
      final a = (await ask("📅  Today's bookings", 'admin'))!;
      expect(a, contains("Today's bookings: 3"));
      expect(a, contains('plus 1 canceled'));
    });

    test('pending approvals lists only pending bookings', () async {
      final a = (await ask('Pending approvals', 'admin'))!;
      expect(a, contains('Waiting for approval: 1'));
      expect(a, contains('Dung'));
    });

    test("today's revenue = services + tips, in VND", () async {
      final a = (await ask("Today's revenue", 'admin'))!;
      expect(a, contains("Today's revenue: 200.000 ₫"));
      expect(a, contains('Services: 180.000 ₫'));
      expect(a, contains('Tips: 20.000 ₫'));
      expect(a, contains('Payments recorded: 2'));
    });

    test('services list mentions inactive ones separately', () async {
      final a = (await ask('List all services', 'admin'))!;
      expect(a, contains('Services (4)'));
      expect(a, contains('Plus 1 inactive service'));
    });

    test('Add Barber / Add Service open the forms', () async {
      expect(await ask('➕  Add Barber', 'admin'), contains('[ADMIN_FORM:ADD_BARBER]'));
      expect(await ask('Add Service', 'admin'), contains('[ADMIN_FORM:ADD_CATALOG]'));
    });

    test('cashiers cannot open the add forms', () async {
      expect(await ask('Add Barber', 'cashier'), isNot(contains('[ADMIN_FORM')));
    });
  });
}
