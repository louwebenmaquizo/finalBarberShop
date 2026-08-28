import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter smoke test renders the app shell', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Liem Barber Shop')),
        ),
      ),
    );

    expect(find.text('Liem Barber Shop'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
