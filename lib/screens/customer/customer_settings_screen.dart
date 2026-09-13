import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../onboarding.dart';
import '../../services/auth_session_service.dart';
import 'edit_profile_dialog.dart';
import 'change_password_dialog.dart';
import 'help_support_dialog.dart';
import 'about_dialog.dart';
import 'notification_settings_dialog.dart';
import 'customer_appointments_screen.dart';
import '../../services/theme_service.dart';

class CustomerSettingsScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const CustomerSettingsScreen({super.key, this.userData});

  @override
  State<CustomerSettingsScreen> createState() => _CustomerSettingsScreenState();
}

class _CustomerSettingsScreenState extends State<CustomerSettingsScreen> {
  late Map<String, dynamic> _userData;

  @override
  void initState() {
    super.initState();
    _userData = Map<String, dynamic>.from(widget.userData ?? {});
  }

  void _showAppearanceDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService.themeModeNotifier,
          builder: (context, currentMode, _) {
            final isDark = AppColors.isDark(context);
            const blueColor = Color(0xFF5BBCFF);
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

  @override
  Widget build(BuildContext context) {
    final displayName =
        _userData['full_name'] ?? _userData['username'] ?? 'Customer';
    final email = _userData['email'] ?? 'No email';
    final phone = _userData['phone'] ?? '';
    final profilePhoto =
        _userData['profile_picture'] ?? _userData['profile_photo'];

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        backgroundColor: AppColors.surface(context),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Profile Section Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(AppColors.isDark(context) ? 0.2 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildSettingsAvatar(profilePhoto, displayName),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          phone,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.edit_outlined, color: Color(0xFF1E88E5)),
                  onPressed: () {
                    showEditProfileDialog(
                      context,
                      userData: _userData,
                      onUpdated: (updated) {
                        setState(() {
                          _userData = updated;
                        });
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          // Settings Section: Account
          _buildSettingsSection(
            context,
            'Account',
            [
              _buildSettingsTile(
                context,
                icon: Icons.person_outline,
                title: 'Edit Profile',
                onTap: () {
                  showEditProfileDialog(
                    context,
                    userData: _userData,
                    onUpdated: (updated) {
                      setState(() {
                        _userData = updated;
                      });
                    },
                  );
                },
              ),
              _buildSettingsTile(
                context,
                icon: Icons.lock_outline,
                title: 'Change Password',
                onTap: () {
                  showChangePasswordDialog(context);
                },
              ),
            ],
          ),

          // Settings Section: Appointments
          _buildSettingsSection(
            context,
            'Appointments',
            [
              _buildSettingsTile(
                context,
                icon: Icons.history,
                title: 'Appointment History',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CustomerAppointmentsScreen(userData: _userData),
                    ),
                  );
                },
              ),
              _buildSettingsTile(
                context,
                icon: Icons.notifications_outlined,
                title: 'Notification Preferences',
                onTap: () {
                  showNotificationSettingsDialog(context);
                },
              ),
            ],
          ),

          // Settings Section: Preferences
          _buildSettingsSection(
            context,
            'Preferences',
            [
              _buildSettingsTile(
                context,
                icon: Icons.palette_outlined,
                title: 'Appearance',
                onTap: _showAppearanceDialog,
              ),
            ],
          ),

          // Settings Section: Support
          _buildSettingsSection(
            context,
            'Support & Legal',
            [
              _buildSettingsTile(
                context,
                icon: Icons.help_outline,
                title: 'Help & Support',
                onTap: () {
                  showHelpSupportModal(context);
                },
              ),
              _buildSettingsTile(
                context,
                icon: Icons.info_outline,
                title: 'About Liem Barber Shop',
                onTap: () {
                  showAboutAppDialog(context);
                },
              ),
            ],
          ),

          // Logout Button
          Container(
            margin: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _showLogoutDialog(context),
                icon: const Icon(Icons.logout, size: 20, color: Colors.white),
                label: Text(
                  'Log Out',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary(context),
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder(context)),
          ),
          child: Column(
            children: children,
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0x1A5BBCFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF1E88E5), size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary(context),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Log Out',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          content: Text(
            'Are you sure you want to log out of your account?',
            style: GoogleFonts.manrope(
              color: AppColors.textSecondary(context),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                AuthSessionService.clearSession();
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
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
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsAvatar(String? photo, String name) {
    const double size = 60.0;
    if (photo != null && photo.trim().isNotEmpty) {
      String clean = photo.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF5BBCFF), width: 2),
          ),
          child: ClipOval(
            child: Image.network(
              clean,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _buildFallbackSettingsAvatar(name, size),
            ),
          ),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(
            base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF5BBCFF), width: 2),
          ),
          child: ClipOval(
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        );
      } catch (_) {}
    }
    return _buildFallbackSettingsAvatar(name, size);
  }

  Widget _buildFallbackSettingsAvatar(String name, double size) {
    final initial =
        (name.trim().isNotEmpty ? name.trim()[0] : 'C').toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x1A5BBCFF),
        border: Border.all(color: const Color(0xFF5BBCFF), width: 2),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.manrope(
            fontSize: size * 0.42,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E88E5),
          ),
        ),
      ),
    );
  }
}
