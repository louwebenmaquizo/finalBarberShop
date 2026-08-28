import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  bool _pushReminders = true;
  bool _smsUpdates = true;
  bool _promoAlerts = false;
  bool _emailReceipts = true;

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
            _buildSwitchTile(
                'Appointment Reminders',
                'Get notified 2 hours prior to your scheduled haircut',
                _pushReminders,
                (val) => setState(() => _pushReminders = val)),
            _buildSwitchTile(
                'SMS Confirmations',
                'Receive booking confirmations via SMS',
                _smsUpdates,
                (val) => setState(() => _smsUpdates = val)),
            _buildSwitchTile(
                'Promotions & Discounts',
                'Exclusive seasonal haircuts & styling discount offers',
                _promoAlerts,
                (val) => setState(() => _promoAlerts = val)),
            _buildSwitchTile(
                'Email Invoices & Receipts',
                'Get digital receipts sent directly to your email',
                _emailReceipts,
                (val) => setState(() => _emailReceipts = val)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
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
            activeColor: const Color(0xFF5BBCFF),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
