/// Centralized input sanitization and XSS mitigation utility.
///
/// Ensures all user inputs across registration, login, profile editing,
/// catalog creation, and appointment booking are sanitized, length-bounded,
/// and stripped of malicious HTML/script injections.
class SecuritySanitizer {
  SecuritySanitizer._();

  static final RegExp _scriptTagRegex = RegExp(
    r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>',
    caseSensitive: false,
    multiLine: true,
  );

  static final RegExp _htmlTagsRegex = RegExp(
    r'<\/?[a-zA-Z][a-zA-Z0-9]*(\s+[^>]*)?\/?>',
    caseSensitive: false,
  );

  static final RegExp _dangerousProtocolsRegex = RegExp(
    r'(javascript:|vbscript:|data:text\/html)',
    caseSensitive: false,
  );

  static final RegExp _eventHandlersRegex = RegExp(
    r'\bon[a-zA-Z]+\s*=',
    caseSensitive: false,
  );

  /// Strips dangerous HTML tags, JavaScript event handlers, and restricts length.
  static String sanitizeText(String? input, {int maxLength = 255}) {
    if (input == null) return '';
    var text = input.trim();
    if (text.isEmpty) return '';

    // Remove null bytes
    text = text.replaceAll('\u0000', '');

    // Strip <script>...</script>
    text = text.replaceAll(_scriptTagRegex, '');

    // Strip dangerous inline event handlers like onload=, onerror=
    text = text.replaceAll(_eventHandlersRegex, '');

    // Strip dangerous protocol URLs
    text = text.replaceAll(_dangerousProtocolsRegex, '');

    // Strip any residual HTML tags
    text = text.replaceAll(_htmlTagsRegex, '');

    // Enforce upper bound length
    if (text.length > maxLength) {
      text = text.substring(0, maxLength);
    }

    return text.trim();
  }

  /// Sanitizes multi-line text (e.g. notes, descriptions, reviews) while preserving newlines.
  static String sanitizeMultiline(String? input, {int maxLength = 1000}) {
    if (input == null) return '';
    var text = input.trim();
    if (text.isEmpty) return '';

    // Remove null bytes and dangerous control characters (except newline, tab)
    text = text.replaceAll('\u0000', '');
    text = text.replaceAll(RegExp(r'[\x01-\x08\x0B\x0C\x0E-\x1F]'), '');

    // Strip scripts and dangerous tags
    text = text.replaceAll(_scriptTagRegex, '');
    text = text.replaceAll(_eventHandlersRegex, '');
    text = text.replaceAll(_dangerousProtocolsRegex, '');
    text = text.replaceAll(_htmlTagsRegex, '');

    if (text.length > maxLength) {
      text = text.substring(0, maxLength);
    }

    return text.trim();
  }

  /// Normalizes and cleans an email string.
  static String sanitizeEmail(String? email) {
    if (email == null) return '';
    var cleaned = email.trim().toLowerCase();
    cleaned = cleaned.replaceAll('\u0000', '');
    // Only allow standard email characters
    cleaned = cleaned.replaceAll(RegExp(r'[^a-z0-9@._+-]'), '');
    return cleaned;
  }

  /// Normalizes and strips unwanted characters from a phone number.
  static String sanitizePhone(String? phone) {
    if (phone == null) return '';
    var cleaned = phone.trim();
    final hasPlus = cleaned.startsWith('+');
    // Strip everything except digits
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length > 20) {
      cleaned = cleaned.substring(0, 20);
    }
    return hasPlus ? '+$cleaned' : cleaned;
  }

  /// Detects potential injection attack patterns.
  static bool hasSuspiciousPattern(String? input) {
    if (input == null || input.isEmpty) return false;
    final lower = input.toLowerCase();
    return lower.contains('<script') ||
        lower.contains('javascript:') ||
        lower.contains('onload=') ||
        lower.contains('onerror=') ||
        lower.contains('union select') ||
        lower.contains('--') && lower.contains(';') ||
        lower.contains('exec(');
  }
}
