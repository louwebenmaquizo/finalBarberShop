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

import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  await ThemeService.init();
  // Manrope ships in assets/google_fonts, so never download fonts at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  TimeoutHttpClient.onConnectionProblem = showConnectionProblem;
  runApp(const MyApp());
}

final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
DateTime? _lastConnectionNotice;

/// Tells the user a request failed because of their connection. Many screens
/// otherwise just show an empty list. Shown at most once every 8 seconds.
void showConnectionProblem() {
  final now = DateTime.now();
  if (_lastConnectionNotice != null &&
      now.difference(_lastConnectionNotice!) < const Duration(seconds: 8)) {
    return;
  }
  _lastConnectionNotice = now;
  appMessengerKey.currentState?.showSnackBar(
    const SnackBar(
      content: Text('Connection problem. Check your internet and try again.'),
      duration: Duration(seconds: 4),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The sign-in screens are designed for light mode only, so the saved
    // dark/light preference applies once someone is signed in.
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        final signedIn = Supabase.instance.client.auth.currentSession != null;
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService.themeModeNotifier,
          builder: (context, themeMode, _) {
            return MaterialApp(
              scaffoldMessengerKey: appMessengerKey,
              title: 'Liem Barber Shop',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: signedIn ? themeMode : ThemeMode.light,
              home: const AuthGate(),
              debugShowCheckedModeBanner: false,
            );
          },
        );
      },
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
            _targetScreen =
                AdminHomeScreen(username: user['username'] as String?);
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
      // The profile could not be loaded (usually no connection). Never guess
      // the role: a signed-in user gets a retry screen instead.
      final hasSession = SupabaseConfig.client.auth.currentSession != null;
      if (mounted) {
        setState(() {
          _targetScreen = hasSession
              ? _ConnectionErrorScreen(onRetry: _checkInitialAuth)
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

class _ConnectionErrorScreen extends StatelessWidget {
  const _ConnectionErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded,
                    size: 56, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  "Can't reach Liem Barber Shop",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Check your internet connection and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
