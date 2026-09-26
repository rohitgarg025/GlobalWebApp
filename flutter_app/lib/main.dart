import 'package:flutter/material.dart';
import 'layout/app_shell.dart';
import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';

void main() {
  AuthService.instance.init();
  runApp(const GlobalBuildestateApp());
}

class GlobalBuildestateApp extends StatelessWidget {
  const GlobalBuildestateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Global Buildestate – Operations Platform',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0066CC),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

/// Shows a splash while restoring the session, the sign-in screen when signed
/// out, and the app shell once authenticated.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;
        if (!auth.initialized) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!auth.isAuthenticated) {
          return const SignInScreen();
        }
        return const AppShell();
      },
    );
  }
}
