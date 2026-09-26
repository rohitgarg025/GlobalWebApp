import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Non-web fallback: a plain button that triggers the programmatic flow.
Widget buildGoogleSignInButton() {
  return ElevatedButton.icon(
    onPressed: () => AuthService.instance.signInWithGoogle(),
    icon: const Icon(Icons.login),
    label: const Text('Sign in with Google'),
  );
}
