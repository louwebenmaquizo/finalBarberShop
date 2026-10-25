import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/notification_service.dart';

void showNotificationSettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const _NotificationSettingsDialogContent(),
  );
}

class _NotificationSettingsDialogContent extends StatefulWidget {
  const _NotificationSettingsDialogContent();

  @override
  State<_NotificationSettingsDialogContent> createState() =>
      _NotificationSettingsDialogContentState();
}

class _NotificationSettingsDialogContentState
    extends State<_NotificationSettingsDialogContent> {
  Map<String, bool>? _values;

  @override
  void initState() {
    super.initState();
    NotificationService.loadPreferences().then((v) {
      if (mounted) setState(() => _values = v);
    });
  }

  void _set(String key, bool value) =>
      setState(() => _values = {...?_values, key: value});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Notification Settings',
                  style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_values == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildSwitchTile(
                  'Appointment Reminders',
                  'Show a reminder in the app when your haircut is within the next day and a half',
                  _values!['reminders']!,
                  (val) => _set('reminders', val)),
              _buildSwitchTile(
                  'Booking Updates',
                  'Show when a booking is received, confirmed, declined, canceled or completed',
                  _values!['booking_updates']!,
                  (val) => _set('booking_updates', val)),
              _buildSwitchTile(
                  'Shop News',
                  'Show welcome messages and news from the shop',
                  _values!['promotions']!,
                  (val) => _set('promotions', val)),
              const SizedBox(height: 8),
              Text(
                'These are in-app notifications (the bell icon). The app does not send SMS or email.',
                style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _values == null
                    ? null
                    : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  await NotificationService.savePreferences(_values!);
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(
                        content: Text('Notification preferences saved!',
                            style: GoogleFonts.manrope()),
                        backgroundColor: Colors.green),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5BBCFF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Save Preferences',
                    style: GoogleFonts.manrope(
                        fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: Colors.grey[600], height: 1.3)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF5BBCFF),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
