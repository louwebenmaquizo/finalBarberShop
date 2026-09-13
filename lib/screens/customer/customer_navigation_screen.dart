import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'customer_home_screen.dart';
import 'customer_catalog_screen.dart';
import 'customer_appointments_screen.dart';
import 'customer_settings_screen.dart';
import '../ai_chat_screen.dart';
import '../../services/theme_service.dart';

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
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _screens = [
      CustomerHomeScreen(
        userData: widget.userData,
      ),
      CustomerCatalogScreen(
        userData: widget.userData,
      ),
      CustomerAppointmentsScreen(
        userData: widget.userData,
      ),
      CustomerSettingsScreen(
        userData: widget.userData,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
            const DraggableAiFloatingButton(),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            border: Border(top: BorderSide(color: AppColors.divider(context), width: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(AppColors.isDark(context) ? 0.3 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: BottomNavigationBar(
            backgroundColor: AppColors.surface(context),
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFF5BBCFF),
            unselectedItemColor: AppColors.textSecondary(context),
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
      ),
    );
  }
}
