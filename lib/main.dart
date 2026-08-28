import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/api_config.dart';
import 'services/auth_session_service.dart';
import 'screens/onboarding.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/barber/barber_home_screen.dart';
import 'screens/auth/password_recovery_screen.dart';
import 'screens/customer/customer_navigation_screen.dart';

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
  bool _isChecking = true;
  Widget _targetScreen = const OnboardingScreen();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            _targetScreen = const PasswordRecoveryScreen();
            _isChecking = false;
          });
        }
      },
    );
    _checkActiveSession();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkActiveSession() async {
    try {
      final session = await AuthSessionService.getSession();
      if (session != null && session.isNotEmpty) {
        final role = session['role']?.toString().toLowerCase();
        if (role == 'admin' || role == 'manager' || role == 'cashier') {
          _targetScreen = AdminHomeScreen(username: session['username']);
        } else if (role == 'barber' || role == 'staff') {
          _targetScreen = BarberHomeScreen(barberData: session);
        } else if (role == 'customer') {
          _targetScreen = CustomerNavigationScreen(userData: session);
        }
      }
    } catch (error) {
      debugPrint('Session check failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFF5BBCFF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.content_cut,
                    size: 36, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(
                  color: Color(0xFF5BBCFF), strokeWidth: 2.5),
            ],
          ),
        ),
      );
    }
    return _targetScreen;
  }
}
