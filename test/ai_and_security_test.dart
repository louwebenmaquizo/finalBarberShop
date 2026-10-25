import 'package:barber/services/password_generator.dart';
import 'package:barber/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateTempPassword', () {
    test('is 12 chars with upper, lower, digit and symbol', () {
      for (var i = 0; i < 200; i++) {
        final pw = generateTempPassword();
        expect(pw.length, 12);
        expect(RegExp(r'[A-Z]').hasMatch(pw), isTrue);
        expect(RegExp(r'[a-z]').hasMatch(pw), isTrue);
        expect(RegExp(r'[0-9]').hasMatch(pw), isTrue);
        expect(RegExp(r'[!@#$%*?]').hasMatch(pw), isTrue);
      }
    });

    test('is not predictable', () {
      final seen = {for (var i = 0; i < 500; i++) generateTempPassword()};
      expect(seen.length, 500);
    });
  });

  group('AiService.extractRequestedCount', () {
    const barberWords = ['barber', 'barbers'];

    test('reads digits and number words', () {
      expect(AiService.extractRequestedCount('give me 2 barbers', keywords: barberWords), 2);
      expect(AiService.extractRequestedCount('recommend one barber', keywords: barberWords), 1);
    });

    test('returns null for "all" or no keyword', () {
      expect(AiService.extractRequestedCount('show all barbers', keywords: barberWords), isNull);
      expect(AiService.extractRequestedCount('what time do you open', keywords: barberWords), isNull);
    });
  });

  group('AiChatException.allowsLocalFallback', () {
    test('only for network, missing function and server errors', () {
      expect(const AiChatException('x').allowsLocalFallback, isTrue);
      expect(const AiChatException('x', status: 404).allowsLocalFallback, isTrue);
      expect(const AiChatException('x', status: 503).allowsLocalFallback, isTrue);
      expect(const AiChatException('x', status: 429).allowsLocalFallback, isFalse);
      expect(const AiChatException('x', status: 403).allowsLocalFallback, isFalse);
      expect(const AiChatException('x', status: 401).allowsLocalFallback, isFalse);
    });
  });
}
