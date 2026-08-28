import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void showTermsAndConditionsModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _TermsModalContent(),
  );
}

class _TermsModalContent extends StatelessWidget {
  const _TermsModalContent();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Terms & Conditions',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
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

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    '1. Acceptance of Terms',
                    'By registering an account, booking an appointment, or using any services provided by Liem Barber Shop, you agree to be bound by these Terms & Conditions. If you do not agree to these terms, please do not use our services.',
                  ),
                  _buildSection(
                    '2. Appointment Booking & Punctuality',
                    '• Appointments can be booked through our mobile app or web platform up to 30 days in advance.\n• Please arrive at least 5-10 minutes prior to your scheduled appointment.\n• If you are more than 15 minutes late without notice, your appointment may be marked as a no-show or rescheduled based on barber availability.',
                  ),
                  _buildSection(
                    '3. Cancellation & Rescheduling Policy',
                    '• Free cancellations and rescheduling are available up to 2 hours before your scheduled appointment time.\n• Repeated last-minute cancellations or missed appointments may require a deposit for future bookings.',
                  ),
                  _buildSection(
                    '4. Pricing & Payment',
                    '• All service prices displayed in the catalog are current and subject to change with notice.\n• Payment is settled in-store via Cash, Credit/Debit Card, GCash, or Maya upon completion of your service.',
                  ),
                  _buildSection(
                    '5. Hygiene & Safety Standards',
                    '• Liem Barber Shop strictly adheres to sanitary standards, including sanitized clippers, fresh razor blades, and clean capes for every customer.\n• Please notify your barber of any skin allergies, sensitivities, or scalp conditions before your service begins.',
                  ),
                  _buildSection(
                    '6. Privacy & Data Protection',
                    '• Your personal information (name, email, phone number) is securely stored and solely used for appointment reminders, customer service, and promotional updates.\n• We do not sell or share your data with third parties.',
                  ),
                  _buildSection(
                    '7. Contact & Inquiries',
                    'If you have questions regarding these terms, please contact us at support@liembarber.com or call us at (02) 8123-4567.',
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Close button
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5BBCFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'I Understand',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
