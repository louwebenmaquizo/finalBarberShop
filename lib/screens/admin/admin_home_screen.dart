import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dashboard_screen.dart';
import 'employee_screen.dart';
import 'catalog_screen.dart';
import 'booking_screen.dart';
import 'settings_screen.dart';
import '../../widgets/notifications_modal.dart';

class AdminHomeScreen extends StatefulWidget {
  final String? username;
  
  const AdminHomeScreen({super.key, this.username});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0; // Default to first screen (Navigation/Dashboard)
  String? _username;

  // Navigation items
  final List<NavItem> _navItems = [
    NavItem(icon: Icons.dashboard, label: 'Dashboard', route: 'dashboard'),
    NavItem(icon: Icons.people, label: 'Employee', route: 'employee'),
    NavItem(icon: Icons.inventory, label: 'Catalog', route: 'catalog'),
    NavItem(icon: Icons.calendar_today, label: 'Booking', route: 'booking'),
    NavItem(icon: Icons.settings, label: 'Settings', route: 'settings'),
  ];

  @override
  void initState() {
    super.initState();
    _username = widget.username ?? 'Admin'; // Use passed username or default
  }

  // Placeholder screens for now
  Widget _getBodyContent() {
    switch (_selectedIndex) {
      case 0: // Navigation/Dashboard
        return _buildDashboardScreen();
      case 1: // Employee
        return _buildEmployeeScreen();
      case 2: // Catalog
        return _buildCatalogScreen();
      case 3: // Booking
        return _buildBookingScreen();
      case 4: // Settings
        return _buildSettingsScreen();
      default:
        return _buildDashboardScreen();
    }
  }

  // Dashboard screen
  Widget _buildDashboardScreen() {
    return const DashboardScreen();
  }

  Widget _buildEmployeeScreen() {
    return const EmployeeScreen();
  }

  // Catalog screen
  Widget _buildCatalogScreen() {
    return const CatalogScreen();
  }

  // Booking screen
  Widget _buildBookingScreen() {
    return const BookingScreen();
  }

  // Settings screen
  Widget _buildSettingsScreen() {
    return const SettingsScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
          // Admin Image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/admin_fes.jpg',
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xB25BBCFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 28,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          // Admin Name - "Hi + username"
          Expanded(
            child: Text(
              'Hi ${_username ?? 'Admin'}',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
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
            child: IconButton(
              icon: Stack(
                children: [
                  const Icon(
                    Icons.notifications_outlined,
                    size: 24,
                    color: Colors.black87,
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                    ),
                  ),
                ],
              ),
              onPressed: () {
                showNotificationsModal(context, isAdmin: true);
              },
            ),
          ),
        ],
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
