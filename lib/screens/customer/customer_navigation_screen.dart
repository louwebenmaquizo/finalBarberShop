import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'customer_home_screen.dart';
import 'customer_catalog_screen.dart';
import 'customer_appointments_screen.dart';
import 'customer_settings_screen.dart';

class CustomerNavigationScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final int initialIndex;

  const CustomerNavigationScreen(
      {super.key, this.userData, this.initialIndex = 0});

  @override
  State<CustomerNavigationScreen> createState() =>
      _CustomerNavigationScreenState();
}

class _CustomerNavigationScreenState extends State<CustomerNavigationScreen> {
  late int _currentIndex;
  int _refreshCounter = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      CustomerHomeScreen(
        key: ValueKey('home_$_refreshCounter'),
        userData: widget.userData,
      ),
      CustomerCatalogScreen(
        key: ValueKey('catalog_$_refreshCounter'),
        userData: widget.userData,
      ),
      CustomerAppointmentsScreen(
        key: ValueKey('appointments_$_refreshCounter'),
        userData: widget.userData,
      ),
      CustomerSettingsScreen(
        key: ValueKey('settings_$_refreshCounter'),
        userData: widget.userData,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
              _refreshCounter++;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xB25BBCFF),
          unselectedItemColor: Colors.grey[600],
          selectedLabelStyle: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.normal,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.store_outlined),
              activeIcon: Icon(Icons.store),
              label: 'Catalog',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today),
              label: 'Booking',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
