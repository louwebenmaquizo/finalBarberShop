import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../onboarding.dart';
import '../../services/auth_session_service.dart';
import '../../widgets/terms_modal.dart';
import '../customer/change_password_dialog.dart';
import '../customer/help_support_dialog.dart';
import '../customer/about_dialog.dart';
import 'admin_profile_screen.dart';

import '../../services/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color blueColor = Color(0xFF5BBCFF);

  void _showAppearanceDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService.themeModeNotifier,
          builder: (context, currentMode, _) {
            final isDark = AppColors.isDark(context);
            return AlertDialog(
              backgroundColor: AppColors.surface(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Appearance',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading:
                        const Icon(Icons.light_mode, color: Colors.orange),
                    title: Text(
                      'Light Mode (Default)',
                      style: GoogleFonts.manrope(
                        fontWeight: currentMode == ThemeMode.light
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    trailing: currentMode == ThemeMode.light
                        ? const Icon(Icons.check_circle, color: blueColor)
                        : null,
                    onTap: () async {
                      await ThemeService.setThemeMode(ThemeMode.light);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Switched to Light Mode')),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.dark_mode, color: Colors.indigoAccent),
                    title: Text(
                      'Dark Mode',
                      style: GoogleFonts.manrope(
                        fontWeight: currentMode == ThemeMode.dark
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    trailing: currentMode == ThemeMode.dark
                        ? const Icon(Icons.check_circle, color: blueColor)
                        : null,
                    onTap: () async {
                      await ThemeService.setThemeMode(ThemeMode.dark);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Switched to Dark Mode')),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.settings_system_daydream,
                        color: isDark ? Colors.tealAccent : Colors.teal),
                    title: Text(
                      'Auto / System',
                      style: GoogleFonts.manrope(
                        fontWeight: currentMode == ThemeMode.system
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    trailing: currentMode == ThemeMode.system
                        ? const Icon(Icons.check_circle, color: blueColor)
                        : null,
                    onTap: () async {
                      await ThemeService.setThemeMode(ThemeMode.system);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Appearance synchronized with system theme')),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAccountDetailsDialog() async {
    final session = await AuthSessionService.getSession();
    if (!mounted || session == null) return;
    final username = session['username']?.toString() ?? 'Admin';
    final role = session['role']?.toString() ?? 'admin';
    final email = session['email']?.toString() ?? '';
    final isActive = session['is_active'] == true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Admin Account Details',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Username', username),
            const SizedBox(height: 8),
            _buildDetailRow('Role', role),
            const SizedBox(height: 8),
            _buildDetailRow('Email', email),
            const SizedBox(height: 8),
            _buildDetailRow('Status', isActive ? 'Active' : 'Inactive'),
            const SizedBox(height: 16),
            Divider(color: AppColors.divider(context)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_reset, color: blueColor),
              title: Text('Change Admin Password',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary(context))),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.pop(context);
                showChangePasswordDialog(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close',
                style: GoogleFonts.manrope(
                    color: blueColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.manrope(
                color: AppColors.textSecondary(context), fontSize: 13)),
        Text(value,
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary(context))),
      ],
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Log Out',
          style: GoogleFonts.manrope(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context)),
        ),
        content: Text(
          'Are you sure you want to log out of your admin account?',
          style: GoogleFonts.manrope(
            fontSize: 14,
            color: AppColors.textSecondary(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.manrope(
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthSessionService.clearSession();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const OnboardingScreen(),
                  ),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Text(
              'Log Out',
              style: GoogleFonts.manrope(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: GoogleFonts.manrope(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 24),
          _buildSettingsItem(
            icon: Icons.palette,
            title: 'Appearance',
            onTap: _showAppearanceDialog,
          ),
          const SizedBox(height: 16),
          _buildSettingsItem(
            icon: Icons.badge_outlined,
            title: 'Account Credentials & Role',
            onTap: _showAccountDetailsDialog,
          ),
          const SizedBox(height: 16),
          _buildSettingsItem(
            icon: Icons.person,
            title: 'Admin Profile & Security',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const AdminProfileScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildSettingsItem(
            icon: Icons.help_outline,
            title: 'Help Center',
            onTap: () => showHelpSupportModal(context),
          ),
          const SizedBox(height: 16),
          _buildSettingsItem(
            icon: Icons.privacy_tip_outlined,
            title: 'Terms and Privacy Policy',
            onTap: () => showTermsAndConditionsModal(context),
          ),
          const SizedBox(height: 16),
          _buildSettingsItem(
            icon: Icons.info_outline,
            title: 'About Liem Barber Shop',
            onTap: () => showAboutAppDialog(context),
          ),
          const SizedBox(height: 16),
          _buildSettingsItem(
            icon: Icons.logout,
            title: 'Log out',
            onTap: _handleLogout,
            isLogout: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isLogout = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(AppColors.isDark(context) ? 0.2 : 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isLogout
                    ? Colors.red.withOpacity(0.1)
                    : blueColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isLogout ? Colors.red : const Color(0xFF1E88E5),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isLogout ? Colors.red : AppColors.textPrimary(context),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary(context),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
