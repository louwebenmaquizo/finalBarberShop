import 'dart:math';

/// Client-side rate limiter and action debouncer.
///
/// Defends against automated brute-force login guessing and rapid-fire duplicate
/// submissions (e.g. double bookings, spamming review submissions).
class RateLimitService {
  RateLimitService._();

  // Identifier (e.g. email) -> List of failed attempt timestamps
  static final Map<String, List<DateTime>> _failedAttempts = {};

  // Identifier -> Locked until timestamp
  static final Map<String, DateTime> _lockouts = {};

  // ActionKey -> Last executed timestamp
  static final Map<String, DateTime> _actionTimestamps = {};

  // Configuration
  static const int maxFailedAttempts = 5;
  static const Duration attemptWindow = Duration(minutes: 1);
  static const Duration baseLockoutDuration = Duration(seconds: 30);

  /// Checks if an identifier (email/phone) is currently rate-limited.
  ///
  /// Returns 0 if not locked, or the remaining seconds until unlock.
  static int getRemainingLockoutSeconds(String identifier) {
    final key = identifier.trim().toLowerCase();
    final lockedUntil = _lockouts[key];
    if (lockedUntil == null) return 0;

    final now = DateTime.now();
    if (now.isAfter(lockedUntil)) {
      _lockouts.remove(key);
      return 0;
    }

    return max(1, lockedUntil.difference(now).inSeconds);
  }

  /// Records a failed authentication attempt and calculates lockout if threshold reached.
  ///
  /// Returns true if the account is now locked.
  static bool recordFailedAttempt(String identifier) {
    final key = identifier.trim().toLowerCase();
    final now = DateTime.now();

    // Clean up attempts older than the rolling window
    final attempts = (_failedAttempts[key] ?? [])
        .where((ts) => now.difference(ts) <= attemptWindow)
        .toList();

    attempts.add(now);
    _failedAttempts[key] = attempts;

    if (attempts.length >= maxFailedAttempts) {
      // Exponential backoff based on attempt excess
      final multiplier = pow(2, attempts.length - maxFailedAttempts).toInt();
      final lockoutDuration = Duration(
        seconds: min(300, baseLockoutDuration.inSeconds * multiplier),
      );
      _lockouts[key] = now.add(lockoutDuration);
      return true;
    }

    return false;
  }

  /// Clears failed attempts and lockouts upon successful authentication.
  static void recordSuccess(String identifier) {
    final key = identifier.trim().toLowerCase();
    _failedAttempts.remove(key);
    _lockouts.remove(key);
  }

  /// Prevents double-submit or rapid-fire actions (debouncer).
  ///
  /// Returns `true` if the action is allowed, `false` if debounced.
  static bool canPerformAction(
    String actionKey, {
    Duration window = const Duration(milliseconds: 1500),
  }) {
    final now = DateTime.now();
    final lastExecuted = _actionTimestamps[actionKey];

    if (lastExecuted != null && now.difference(lastExecuted) < window) {
      return false; // Throttled
    }

    _actionTimestamps[actionKey] = now;
    return true;
  }

  /// Clears in-memory rate-limit state (useful for test suites or manual reset).
  static void resetAll() {
    _failedAttempts.clear();
    _lockouts.clear();
    _actionTimestamps.clear();
  }
}
