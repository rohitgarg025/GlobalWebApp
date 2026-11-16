import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart' show ApiService;

class AuthUser {
  final int id;
  final String email;
  final String? name;
  final String? picture;
  final String role;
  final List<String> modules;

  const AuthUser({
    required this.id,
    required this.email,
    this.name,
    this.picture,
    required this.role,
    required this.modules,
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as int,
        email: j['email'] as String,
        name: j['name'] as String?,
        picture: j['picture'] as String?,
        role: j['role'] as String,
        modules: (j['modules'] as List).cast<String>(),
      );
}

/// App-wide authentication state. Holds the backend session JWT and the
/// signed-in user's profile + accessible modules.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _tokenKey = 'auth_token';

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  bool _initialized = false;
  bool _signingIn = false;
  String? _token;
  AuthUser? _user;
  String? _error;

  bool get initialized => _initialized;
  bool get signingIn => _signingIn;
  bool get isAuthenticated => _token != null && _user != null;
  AuthUser? get user => _user;
  String? get error => _error;
  Set<String> get modules => _user?.modules.toSet() ?? {};
  bool get isAdmin => _user?.role == 'admin';

  /// Static access for API clients.
  static Map<String, String> get authHeaders {
    final t = instance._token;
    return t == null ? {} : {'Authorization': 'Bearer $t'};
  }

  /// Restore a stored session and start listening for Google sign-in events
  /// (the web "Sign in with Google" button reports through this stream).
  Future<void> init() async {
    _googleSignIn.onCurrentUserChanged.listen((account) async {
      if (account != null && !isAuthenticated) {
        await _loginWithGoogleAccount(account);
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_tokenKey);
      if (stored != null) {
        _token = stored;
        final me = await http.get(
          Uri.parse('${ApiService.baseUrl}/api/auth/me'),
          headers: {'Authorization': 'Bearer $stored'},
        ).timeout(const Duration(seconds: 10));
        if (me.statusCode == 200) {
          _user = AuthUser.fromJson(jsonDecode(me.body) as Map<String, dynamic>);
        } else {
          await _clearSession();
        }
      }
    } catch (_) {
      _token = null;
      _user = null;
    }
    _initialized = true;
    notifyListeners();

    // Non-web platforms can attempt silent sign-in; on web the GIS button flow
    // handles this via onCurrentUserChanged.
    if (!kIsWeb && !isAuthenticated) {
      try {
        await _googleSignIn.signInSilently();
      } catch (_) {}
    }
  }

  /// Programmatic sign-in for non-web platforms (web uses the rendered button).
  Future<void> signInWithGoogle() async {
    try {
      _error = null;
      final account = await _googleSignIn.signIn();
      if (account != null) await _loginWithGoogleAccount(account);
    } catch (e) {
      _error = 'Sign-in failed: $e';
      notifyListeners();
    }
  }

  /// Dev-mode shortcut: skips Google OAuth, gets a real JWT from the backend.
  Future<void> signInAsDevUser() async {
    _signingIn = true;
    _error = null;
    notifyListeners();
    try {
      final res = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/auth/dev-login'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        String detail = 'Dev login failed (${res.statusCode}).';
        try {
          detail = (jsonDecode(res.body) as Map)['detail']?.toString() ?? detail;
        } catch (_) {}
        throw Exception(detail);
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _token = data['token'] as String;
      _user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      await _clearSession();
    } finally {
      _signingIn = false;
      notifyListeners();
    }
  }

  Future<void> _loginWithGoogleAccount(GoogleSignInAccount account) async {
    _signingIn = true;
    _error = null;
    notifyListeners();
    try {
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        throw Exception('Google did not return an ID token.');
      }
      final res = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        String detail = 'Sign-in was rejected by the server.';
        try {
          detail = (jsonDecode(res.body) as Map)['detail']?.toString() ?? detail;
        } catch (_) {}
        throw Exception(detail);
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _token = data['token'] as String;
      _user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      await _clearSession();
    } finally {
      _signingIn = false;
      notifyListeners();
    }
  }

  /// Refresh profile/modules from the backend (e.g. after a role change).
  Future<void> refreshProfile() async {
    if (_token == null) return;
    try {
      final me = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/auth/me'),
        headers: authHeaders,
      ).timeout(const Duration(seconds: 10));
      if (me.statusCode == 200) {
        _user = AuthUser.fromJson(jsonDecode(me.body) as Map<String, dynamic>);
        notifyListeners();
      } else if (me.statusCode == 401) {
        await signOut();
      }
    } catch (_) {}
  }

  Future<void> signOut() async {
    await _clearSession();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    notifyListeners();
  }

  /// Called by API clients when the backend answers 401.
  static void handleUnauthorized() {
    if (instance.isAuthenticated) instance.signOut();
  }

  Future<void> _clearSession() async {
    _token = null;
    _user = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (_) {}
  }
}
