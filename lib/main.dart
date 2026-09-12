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
  bool _isAuthChecking = false; // guard against concurrent checks
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialAuth();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) async {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            _targetScreen = const PasswordRecoveryScreen();
            _isChecking = false;
          });
        } else if (state.event == AuthChangeEvent.signedIn) {
          // Small delay to let Supabase fully settle the session (especially
          // needed for web after Google OAuth redirect)
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
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
    // Prevent concurrent checks from racing each other
    if (_isAuthChecking) return;
    _isAuthChecking = true;
    if (mounted) setState(() => _isChecking = true);

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
        } else if (role == 'barber' || role == 'staff') {
          setState(() {
            _targetScreen = BarberHomeScreen(barberData: user);
            _isChecking = false;
          });
        } else {
          // Customer: if first time / profile not completed, go to CompleteProfileScreen
          if (!isProfileCompleted) {
            setState(() {
              _targetScreen = CompleteProfileScreen(userData: user);
              _isChecking = false;
            });
          } else {
            setState(() {
              _targetScreen = CustomerNavigationScreen(userData: user);
              _isChecking = false;
            });
          }
        }
      } else {
        setState(() {
          _targetScreen = const OnboardingScreen();
          _isChecking = false;
        });
      }
    } catch (_) {
      // Only fall back to onboarding if no current session exists
      final hasSession = SupabaseConfig.client.auth.currentSession != null;
      if (mounted) {
        setState(() {
          _targetScreen = hasSession
              ? _targetScreen // keep current screen if already set
              : const OnboardingScreen();
          _isChecking = false;
        });
      }
    } finally {
      _isAuthChecking = false;
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
