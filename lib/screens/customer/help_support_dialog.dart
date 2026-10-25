import 'package:flutter/material.dart';
import '../../services/theme_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/shop_info.dart';

void showHelpSupportModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _HelpSupportModalContent(),
  );
}

class _HelpSupportModalContent extends StatelessWidget {
  const _HelpSupportModalContent();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.cardBorder(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Help & Support',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Quick Contact Cards
                Text('Contact Us',
                    style: GoogleFonts.manrope(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildContactCard(
                        icon: Icons.phone,
                        title: 'Phone',
                        subtitle: ShopInfo.phoneDisplay,
                        color: Colors.green,
                        onTap: () => _openContact(
                          context,
                          Uri(scheme: 'tel', path: ShopInfo.phoneDial),
                          fallback: ShopInfo.phoneDisplay,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildContactCard(
                        icon: Icons.email_outlined,
                        title: 'Email',
                        subtitle: ShopInfo.email,
                        color: const Color(0xFF1E88E5),
                        onTap: () => _openContact(
                          context,
                          Uri(
                            scheme: 'mailto',
                            path: ShopInfo.email,
                            query: 'subject=Liem%20Barber%20Shop%20app%20support',
                          ),
                          fallback: ShopInfo.email,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // FAQs
                Text('Frequently Asked Questions',
                    style: GoogleFonts.manrope(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildFaqItem(
                  'How do I book an appointment?',
                  'Go to the Catalog or Home screen, pick your preferred service and favorite barber, select your date and time slot, and confirm your booking.',
                ),
                _buildFaqItem(
                  'Can I reschedule or cancel?',
                  'Yes. Go to "Appointments", find your booking, and tap "Reschedule" or "Cancel". You can change or cancel a booking until your service starts.',
                ),
                _buildFaqItem(
                  'What payment methods are accepted?',
                  'We accept Cash, GCash, Maya, Visa, Mastercard, and Debit Cards upon completion of your service at our branch.',
                ),
                _buildFaqItem(
                  'Where is Liem Barber Shop located?',
                  '${ShopInfo.address}. ${ShopInfo.bookingHoursLabel}.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 2),
            Text(subtitle,
                style:
                    GoogleFonts.manrope(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ExpansionTile(
        title: Text(question,
            style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(answer,
              style: GoogleFonts.manrope(
                  fontSize: 13, color: Colors.grey[700], height: 1.5)),
        ],
      ),
    );
  }
}

/// Opens the phone dialer or email app. If the device has no app for it,
/// shows the number/address so the customer can copy it instead.
Future<void> _openContact(BuildContext context, Uri uri,
    {required String fallback}) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No app available to open this. Contact us at $fallback')),
    );
  }
}
