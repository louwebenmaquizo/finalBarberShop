import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dashboard_screen.dart';
import 'employee_screen.dart';
import 'catalog_screen.dart';
import 'booking_screen.dart';
import 'settings_screen.dart';
import 'admin_profile_screen.dart';
import '../../services/auth_session_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/notifications_modal.dart';
import '../ai_chat_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  final String? username;

  const AdminHomeScreen({super.key, this.username});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0; // Default to first screen (Navigation/Dashboard)
  String? _username;
  String? _profilePhoto;

  // Navigation items
  final List<NavItem> _navItems = [
    NavItem(icon: Icons.dashboard, label: 'Dashboard', route: 'dashboard'),
    NavItem(icon: Icons.people, label: 'Employee', route: 'employee'),
    NavItem(icon: Icons.inventory, label: 'Catalog', route: 'catalog'),
    NavItem(icon: Icons.calendar_today, label: 'Booking', route: 'booking'),
    NavItem(icon: Icons.settings, label: 'Settings', route: 'settings'),
  ];

  late final List<Widget> _adminScreens;

  @override
  void initState() {
    super.initState();
    _username = widget.username ?? 'Admin';
    _adminScreens = const [
      DashboardScreen(),
      EmployeeScreen(),
      CatalogScreen(),
      BookingScreen(),
      SettingsScreen(),
    ];
    _loadAdminSession();
    NotificationService.refreshUnreadCount(isAdmin: true);
  }

  Future<void> _loadAdminSession() async {
    try {
      final session = await AuthSessionService.getSession();
      if (session != null && mounted) {
        setState(() {
          _username = session['full_name'] ?? session['username'] ?? widget.username ?? 'Admin';
          _profilePhoto = session['profile_photo'] ?? session['profile_picture'];
        });
      }
    } catch (_) {}
  }

  Widget _getBodyContent() {
    return IndexedStack(
      index: _selectedIndex,
      children: _adminScreens,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        floatingActionButton: const Padding(
          padding: EdgeInsets.only(bottom: 72.0),
          child: AiFloatingButton(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header
              _buildHeader(),
              // Body
              Expanded(
                child: _getBodyContent(),
              ),
              // Footer Navigation
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Admin Image (Tappable to edit profile)
          GestureDetector(
            onTap: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const AdminProfileScreen()),
              );
              if (updated == true) {
                _loadAdminSession();
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildHeaderAvatar(),
            ),
          ),
          const SizedBox(width: 16),
          // Admin Name - "Hi + username" (Tappable)
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final updated = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AdminProfileScreen()),
                );
                if (updated == true) {
                  _loadAdminSession();
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hi ${_username ?? 'Admin'}',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Administrator',
                    style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1E88E5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Notification Button in a box
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.grey[300]!,
                width: 1,
              ),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: NotificationService.unreadCountNotifier,
              builder: (context, unreadCount, _) {
                return IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.notifications_outlined,
                        size: 24,
                        color: Colors.black87,
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E88E5),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 14,
                              minHeight: 14,
                            ),
                            child: Center(
                              child: Text(
                                unreadCount > 9 ? '9+' : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () {
                    showNotificationsModal(context, isAdmin: true);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAvatar() {
    if (_profilePhoto != null && _profilePhoto!.trim().isNotEmpty) {
      final clean = _profilePhoto!.trim();
      if (clean.startsWith('assets/')) {
        return Image.asset(clean, width: 48, height: 48, fit: BoxFit.cover);
      }
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return Image.network(
          clean,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(
              'assets/images/admin_fes.jpg',
              width: 48,
              height: 48,
              fit: BoxFit.cover),
        );
      }
      try {
        final base64Data = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(
            base64Data.replaceAll('\n', '').replaceAll('\r', '').trim());
        return Image.memory(bytes, width: 48, height: 48, fit: BoxFit.cover);
      } catch (_) {}
    }
    return Image.asset(
      'assets/images/admin_fes.jpg',
      width: 48,
      height: 48,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xB25BBCFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.person, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _navItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isSelected = _selectedIndex == index;

            return _buildNavItem(item, index, isSelected);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNavItem(NavItem item, int index, bool isSelected) {
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
          _loadAdminSession();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                color: isSelected
                    ? const Color(0xB25BBCFF) // Blue color when selected
                    : Colors.grey[400],
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? const Color(0xB25BBCFF) // Blue color when selected
                      : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper class for navigation items
class NavItem {
  final IconData icon;
  final String label;
  final String route;

  NavItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}
