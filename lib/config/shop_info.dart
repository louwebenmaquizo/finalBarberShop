import 'package:flutter/material.dart';

/// Shop details and booking rules shown and used across the app. Change them
/// here only; every screen reads from this file.
///
/// The booking limits mirror the database rules in
/// supabase/migrations/202610170001_security_hardening.sql (create_appointment);
/// keep both in sync.
class ShopInfo {
  ShopInfo._();

  static const String name = 'Liem Barber Shop';

  // TODO(owner): replace the placeholder contact details with the real ones.
  static const String phoneDisplay = '+63 (02) 8123-4567';
  static const String phoneDial = '+63281234567';
  static const String email = 'support@liembarber.com';
  static const String address = '123 Barber Street, Metro Manila';

  /// First and last bookable start times, in 30-minute steps.
  static const TimeOfDay firstSlot = TimeOfDay(hour: 8, minute: 0);
  static const TimeOfDay lastSlot = TimeOfDay(hour: 18, minute: 0);
  static const Duration slotStep = Duration(minutes: 30);

  /// Same limits as create_appointment in the database.
  static const int maxUpcomingBookings = 3;
  static const int maxDaysAhead = 90;

  static List<TimeOfDay> get bookingSlots {
    final slots = <TimeOfDay>[];
    var minutes = firstSlot.hour * 60 + firstSlot.minute;
    final last = lastSlot.hour * 60 + lastSlot.minute;
    while (minutes <= last) {
      slots.add(TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
      minutes += slotStep.inMinutes;
    }
    return slots;
  }

  /// True when [time] is a start time customers may book.
  static bool isBookableTime(TimeOfDay time) {
    final m = time.hour * 60 + time.minute;
    return m >= firstSlot.hour * 60 + firstSlot.minute &&
        m <= lastSlot.hour * 60 + lastSlot.minute;
  }

  static String formatTime(TimeOfDay t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// e.g. "Daily, bookings from 8:00 AM to 6:00 PM"
  static String get bookingHoursLabel =>
      'Daily, bookings from ${formatTime(firstSlot)} to ${formatTime(lastSlot)}';
}
