import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/google_sign_in_button_stub.dart'
    if (dart.library.js_interop) '../widgets/google_sign_in_button_web.dart';

// ─── Dev / test mode button ───────────────────────────────────────────────────

class _DevLoginButton extends StatelessWidget {
  const _DevLoginButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          foregroundColor: Colors.grey.shade700,
        ),
        onPressed: () => AuthService.instance.signInAsDevUser(),
        icon: const Icon(Icons.developer_mode_outlined, size: 18),
        label: const Text('Skip — Enter as Dev / Admin', style: TextStyle(fontSize: 13)),
      ),
    );
  }
}

const Color _kBrand = Color(0xFF0066CC);

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _kBrand,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.domain, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Global Buildestate',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _kBrand,
                  ),
                ),
                const Text(
                  'Operations Platform',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Sign in with your Google account to continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                if (auth.signingIn)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  )
                else ...[
                  buildGoogleSignInButton(),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DevLoginButton(),
                ],
                if (auth.error != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      auth.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'New users are signed in as guests with access to the '
                  'Report Transformer. Contact an administrator for wider access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
