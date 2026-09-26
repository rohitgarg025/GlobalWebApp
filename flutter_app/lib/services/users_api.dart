import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart' show ApiService;
import 'auth_service.dart';

class ManagedUser {
  final int id;
  final String email;
  final String? name;
  final String? picture;
  final String role;
  final List<String> modules;
  final String? lastLoginAt;

  const ManagedUser({
    required this.id,
    required this.email,
    this.name,
    this.picture,
    required this.role,
    required this.modules,
    this.lastLoginAt,
  });

  factory ManagedUser.fromJson(Map<String, dynamic> j) => ManagedUser(
        id: j['id'] as int,
        email: j['email'] as String,
        name: j['name'] as String?,
        picture: j['picture'] as String?,
        role: j['role'] as String,
        modules: (j['modules'] as List).cast<String>(),
        lastLoginAt: j['last_login_at'] as String?,
      );
}

class Role {
  final int id;
  final String name;
  final List<String> modules;
  final bool isSystem;

  const Role({
    required this.id,
    required this.name,
    required this.modules,
    required this.isSystem,
  });

  factory Role.fromJson(Map<String, dynamic> j) => Role(
        id: j['id'] as int,
        name: j['name'] as String,
        modules: (j['modules'] as List).cast<String>(),
        isSystem: j['is_system'] as bool,
      );
}

/// All module ids the backend recognises, with display labels.
const Map<String, String> kModuleLabels = {
  'report_transformer': 'Report Transformer',
  'quantity_sheet': 'Quantity Sheet',
  'project_schedule': 'Project Schedule',
  'hindrance_register': 'Hindrance Register',
  'user_management': 'User Management',
};

class UsersApi {
  static String get _base => '${ApiService.baseUrl}/api';

  static Map<String, String> get _headers =>
      {'Content-Type': 'application/json', ...AuthService.authHeaders};

  static Never _fail(http.Response res) {
    if (res.statusCode == 401) AuthService.handleUnauthorized();
    String detail = 'Request failed (${res.statusCode})';
    try {
      final err = jsonDecode(res.body);
      if (err is Map && err['detail'] != null) detail = err['detail'].toString();
    } catch (_) {}
    throw Exception(detail);
  }

  static Future<List<ManagedUser>> listUsers() async {
    final res = await http
        .get(Uri.parse('$_base/users'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) _fail(res);
    return (jsonDecode(res.body) as List)
        .map((e) => ManagedUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<ManagedUser> assignRole(int userId, int roleId) async {
    final res = await http
        .put(
          Uri.parse('$_base/users/$userId/role'),
          headers: _headers,
          body: jsonEncode({'role_id': roleId}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) _fail(res);
    return ManagedUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<List<Role>> listRoles() async {
    final res = await http
        .get(Uri.parse('$_base/roles'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) _fail(res);
    return (jsonDecode(res.body) as List)
        .map((e) => Role.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Role> createRole(String name, List<String> modules) async {
    final res = await http
        .post(
          Uri.parse('$_base/roles'),
          headers: _headers,
          body: jsonEncode({'name': name, 'modules': modules}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) _fail(res);
    return Role.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<Role> updateRole(int roleId,
      {String? name, List<String>? modules}) async {
    final res = await http
        .put(
          Uri.parse('$_base/roles/$roleId'),
          headers: _headers,
          body: jsonEncode({
            if (name != null) 'name': name,
            if (modules != null) 'modules': modules,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) _fail(res);
    return Role.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<void> deleteRole(int roleId) async {
    final res = await http
        .delete(Uri.parse('$_base/roles/$roleId'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) _fail(res);
  }
}
