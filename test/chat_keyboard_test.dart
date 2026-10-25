import 'package:barber/screens/ai_chat_screen.dart';
import 'package:barber/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// With the keyboard open, the chat input must sit directly above the
/// keyboard (no keyboard-sized gap between them).
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(
      url: 'http://localhost:9',
      publishableKey: 'sb_publishable_test',
    );
  });

  testWidgets('chat input sits directly above the keyboard', (tester) async {
    const screen = Size(412, 915);
    const keyboard = 300.0;
    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);

    final previous = FlutterError.onError;
    FlutterError.onError = (_) {}; // unreachable backend errors are expected
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const AiChatScreen()),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    final inputBottom = tester.getBottomLeft(find.byType(TextField).last).dy;
    final keyboardTop = screen.height - keyboard;

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    FlutterError.onError = previous;

    expect(inputBottom, lessThanOrEqualTo(keyboardTop));
    expect(keyboardTop - inputBottom, lessThan(40),
        reason: 'gap between input and keyboard was ${keyboardTop - inputBottom}px');
  });
}
