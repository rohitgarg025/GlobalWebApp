import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart' show ApiService;
import 'auth_service.dart';

class Project {
  final int id;
  final String name;
  final String? code;
  final String? location;
  final String? clientName;
  final String status;
  final String? createdAt;
  final String? createdBy;

  const Project({
    required this.id,
    required this.name,
    this.code,
    this.location,
    this.clientName,
    required this.status,
    this.createdAt,
    this.createdBy,
  });

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as int,
        name: j['name'] as String,
        code: j['code'] as String?,
        location: j['location'] as String?,
        clientName: j['client_name'] as String?,
        status: j['status'] as String? ?? 'active',
        createdAt: j['created_at'] as String?,
        createdBy: j['created_by'] as String?,
      );
}

class ProjectApi {
  static String get _base => '${ApiService.baseUrl}/api';
  static Map<String, String> get _auth => AuthService.authHeaders;

  static void _check401(http.Response res) {
    if (res.statusCode == 401) AuthService.handleUnauthorized();
  }

  static Future<T> _get<T>(String path, T Function(dynamic) parse) async {
    final res = await http
        .get(Uri.parse('$_base$path'), headers: _auth)
        .timeout(const Duration(seconds: 15));
    _check401(res);
    if (res.statusCode != 200) throw Exception('GET $path failed (${res.statusCode})');
    return parse(jsonDecode(res.body));
  }

  static Future<T> _post<T>(
    String path,
    Map<String, dynamic> body,
    T Function(dynamic) parse, {
    int successCode = 200,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base$path'),
          headers: {'Content-Type': 'application/json', ..._auth},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    _check401(res);
    if (res.statusCode != successCode && res.statusCode != 200 && res.statusCode != 201) {
      String detail = 'Request failed (${res.statusCode})';
      try {
        final err = jsonDecode(res.body);
        if (err is Map && err['detail'] != null) detail = err['detail'].toString();
      } catch (_) {}
      throw Exception(detail);
    }
    return parse(jsonDecode(res.body));
  }

  static Future<T> _patch<T>(
    String path,
    Map<String, dynamic> body,
    T Function(dynamic) parse,
  ) async {
    final res = await http
        .patch(
          Uri.parse('$_base$path'),
          headers: {'Content-Type': 'application/json', ..._auth},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    _check401(res);
    if (res.statusCode != 200) {
      String detail = 'Request failed (${res.statusCode})';
      try {
        final err = jsonDecode(res.body);
        if (err is Map && err['detail'] != null) detail = err['detail'].toString();
      } catch (_) {}
      throw Exception(detail);
    }
    return parse(jsonDecode(res.body));
  }

  static Future<void> _delete(String path) async {
    final res = await http
        .delete(Uri.parse('$_base$path'), headers: _auth)
        .timeout(const Duration(seconds: 10));
    _check401(res);
    if (res.statusCode != 204 && res.statusCode != 200) {
      String detail = 'Delete failed (${res.statusCode})';
      try {
        final err = jsonDecode(res.body);
        if (err is Map && err['detail'] != null) detail = err['detail'].toString();
      } catch (_) {}
      throw Exception(detail);
    }
  }

  static Future<List<Project>> listProjects({bool includeArchived = false}) => _get(
        '/projects${includeArchived ? '?include_archived=true' : ''}',
        (j) => (j as List).map((e) => Project.fromJson(e as Map<String, dynamic>)).toList(),
      );

  static Future<Project> createProject({
    required String name,
    String? code,
    String? location,
    String? clientName,
  }) =>
      _post(
        '/projects',
        {
          'name': name,
          if (code != null && code.isNotEmpty) 'code': code,
          if (location != null && location.isNotEmpty) 'location': location,
          if (clientName != null && clientName.isNotEmpty) 'client_name': clientName,
        },
        (j) => Project.fromJson(j as Map<String, dynamic>),
        successCode: 201,
      );

  static Future<Project> updateProject(
    int id, {
    String? name,
    String? code,
    String? location,
    String? clientName,
    String? status,
  }) =>
      _patch(
        '/projects/$id',
        {
          if (name != null) 'name': name,
          if (code != null) 'code': code,
          if (location != null) 'location': location,
          if (clientName != null) 'client_name': clientName,
          if (status != null) 'status': status,
        },
        (j) => Project.fromJson(j as Map<String, dynamic>),
      );

  static Future<Project> archiveProject(int id) =>
      _post('/projects/$id/archive', {}, (j) => Project.fromJson(j as Map<String, dynamic>));

  static Future<void> deleteProject(int id) => _delete('/projects/$id');

  // ── Floors ────────────────────────────────────────────────────────────────

  static Future<List<ProjectFloor>> listFloors(int projectId) => _get(
        '/projects/$projectId/floors',
        (j) => (j as List)
            .map((e) => ProjectFloor.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static Future<ProjectFloor> createFloor(int projectId, String name) => _post(
        '/projects/$projectId/floors',
        {'name': name},
        (j) => ProjectFloor.fromJson(j as Map<String, dynamic>),
        successCode: 201,
      );

  static Future<void> deleteFloor(int floorId) => _delete('/projects/floors/$floorId');

  static Future<List<ProjectFloor>> reorderFloors(
          int projectId, List<int> floorIds) =>
      _post(
        '/projects/$projectId/floors/reorder',
        {'floor_ids': floorIds},
        (j) => (j as List)
            .map((e) => ProjectFloor.fromJson(e as Map<String, dynamic>))
            .toList(),
        successCode: 200,
      );
}

class ProjectFloor {
  final int id;
  final int projectId;
  final String name;
  final int displayOrder;

  const ProjectFloor(
      {required this.id,
      required this.projectId,
      required this.name,
      required this.displayOrder});

  factory ProjectFloor.fromJson(Map<String, dynamic> j) => ProjectFloor(
        id: j['id'] as int,
        projectId: j['project_id'] as int,
        name: j['name'] as String,
        displayOrder: j['display_order'] as int? ?? 0,
      );
}
