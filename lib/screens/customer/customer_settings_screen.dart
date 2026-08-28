import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../auth/login_screen.dart';
import '../../services/auth_session_service.dart';
import 'edit_profile_dialog.dart';
import 'change_password_dialog.dart';
import 'help_support_dialog.dart';
import 'about_dialog.dart';
import 'notification_settings_dialog.dart';
import 'customer_appointments_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final displayName =
        _userData['full_name'] ?? _userData['username'] ?? 'Customer';
    final email = _userData['email'] ?? 'No email';
    final phone = _userData['phone'] ?? '';
    final profilePhoto =
        _userData['profile_picture'] ?? _userData['profile_photo'];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Profile Section Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
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
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          phone,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: Colors.grey[500],
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
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!),
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
          color: Colors.black87,
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Log Out',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to log out of your account?',
            style: GoogleFonts.manrope(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await AuthSessionService.clearSession();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
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
