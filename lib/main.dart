import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/api_config.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/auth/complete_profile_screen.dart';
import 'screens/auth/password_recovery_screen.dart';
import 'screens/barber/barber_home_screen.dart';
import 'screens/customer/customer_navigation_screen.dart';
import 'screens/onboarding.dart';
import 'services/auth_session_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  GoogleFonts.config.allowRuntimeFetching = true;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liem Barber Shop',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5BBCFF)),
        useMaterial3: true,
        textTheme: GoogleFonts.manropeTextTheme(
          Theme.of(context).textTheme,  
        ),
      ),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Widget _targetScreen = const OnboardingScreen();
  bool _isChecking = true;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialAuth();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            _targetScreen = const PasswordRecoveryScreen();
            _isChecking = false;
          });
        } else if (state.event == AuthChangeEvent.signedIn) {
          _checkInitialAuth();
        } else if (state.event == AuthChangeEvent.signedOut) {
          setState(() {
            _targetScreen = const OnboardingScreen();
            _isChecking = false;
          });
        }
      },
    );
  }

  Future<void> _checkInitialAuth() async {
    try {
      final user = await AuthSessionService.getSession();
      if (!mounted) return;

      if (user != null) {
        final role = (user['role'] ?? '').toString().toLowerCase();
        final isProfileCompleted = user['is_profile_completed'] == true;

        if (role == 'admin' || role == 'manager' || role == 'cashier') {
          setState(() {
            _targetScreen = AdminHomeScreen(username: user['username'] as String?);
            _isChecking = false;
          });
          return;
        } else if (role == 'barber' || role == 'staff') {
          setState(() {
            _targetScreen = BarberHomeScreen(barberData: user);
            _isChecking = false;
          });
          return;
        } else {
          // Automatic login to Customer Navigation Screen for all users
          setState(() {
            _targetScreen = CustomerNavigationScreen(userData: user);
            _isChecking = false;
          });
          return;
        }
      }

      setState(() {
        _targetScreen = const OnboardingScreen();
        _isChecking = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _targetScreen = const OnboardingScreen();
          _isChecking = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5BBCFF)),
          ),
        ),
      );
    }
    return _targetScreen;
  }
}
