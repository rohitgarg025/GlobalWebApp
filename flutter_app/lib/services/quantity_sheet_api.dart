import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/quantity_sheet/qs_models.dart';
import 'api_service.dart' show ApiService;

class QsApi {
  static String get _base => '${ApiService.baseUrl}/api/quantity-sheet';

  static Future<T> _get<T>(String path, T Function(dynamic) parse) async {
    final res = await http.get(Uri.parse('$_base$path')).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('GET $path failed (${res.statusCode})');
    }
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
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != successCode && res.statusCode != 200 && res.statusCode != 201) {
      String detail = 'Request failed (${res.statusCode})';
      try {
        final err = jsonDecode(res.body);
        if (err is Map && err['detail'] != null) {
          final d = err['detail'];
          if (d is Map && d['errors'] is List) {
            detail = (d['errors'] as List).join('\n');
          } else {
            detail = d.toString();
          }
        }
      } catch (_) {}
      throw Exception(detail);
    }
    return parse(jsonDecode(res.body));
  }

  static Future<void> _delete(String path) async {
    await http.delete(Uri.parse('$_base$path')).timeout(const Duration(seconds: 10));
  }

  // ── Projects ──────────────────────────────────────────────────────────────

  static Future<List<QsProject>> listProjects() =>
      _get('/projects', (j) => (j as List).map((e) => QsProject.fromJson(e)).toList());

  static Future<QsProject> createProject(String name) =>
      _post('/projects', {'name': name}, (j) => QsProject.fromJson(j), successCode: 201);

  static Future<void> deleteProject(int id) => _delete('/projects/$id');

  // ── Floors ────────────────────────────────────────────────────────────────

  static Future<List<QsFloor>> listFloors(int projectId) => _get(
        '/projects/$projectId/floors',
        (j) => (j as List).map((e) => QsFloor.fromJson(e)).toList(),
      );

  static Future<QsFloor> createFloor(int projectId, String name, int order) =>
      _post('/projects/$projectId/floors', {'name': name, 'display_order': order},
          (j) => QsFloor.fromJson(j), successCode: 201);

  static Future<void> deleteFloor(int floorId) => _delete('/floors/$floorId');

  static Future<List<QsFloor>> reorderFloors(int projectId, List<int> floorIds) =>
      _post('/projects/$projectId/floors/reorder', {'floor_ids': floorIds},
          (j) => (j as List).map((e) => QsFloor.fromJson(e)).toList());

  // ── Activities ────────────────────────────────────────────────────────────

  static Future<List<QsActivity>> listActivities() =>
      _get('/activities', (j) => (j as List).map((e) => QsActivity.fromJson(e)).toList());

  static Future<QsActivity> createActivity(String name, String unit) =>
      _post('/activities', {'name': name, 'unit': unit}, (j) => QsActivity.fromJson(j),
          successCode: 201);

  static Future<void> deleteActivity(int id) => _delete('/activities/$id');

  // ── Data ──────────────────────────────────────────────────────────────────

  static Future<QsProjectData> getProjectData(int projectId, String month) =>
      _get('/projects/$projectId/data?month=$month', (j) => QsProjectData.fromJson(j));

  static Future<Map<String, dynamic>> submitEntries({
    required int projectId,
    required String month,
    required String submittedBy,
    required List<Map<String, dynamic>> rows,
  }) =>
      _post(
        '/projects/$projectId/submit',
        {'month': month, 'submitted_by': submittedBy, 'rows': rows},
        (j) => j as Map<String, dynamic>,
      );

  // ── Overruns ──────────────────────────────────────────────────────────────

  static Future<List<QsOverrun>> getOverruns({int? projectId}) => _get(
        '/overruns${projectId != null ? '?project_id=$projectId' : ''}',
        (j) => (j as List).map((e) => QsOverrun.fromJson(e)).toList(),
      );

  // ── Compare ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getComparison(int activityId, String month) =>
      _get('/compare?activity_id=$activityId&month=$month', (j) => j as Map<String, dynamic>);

  // ── Export ────────────────────────────────────────────────────────────────

  static Future<Uint8List> exportExcel(int projectId, String month) async {
    final res = await http
        .get(Uri.parse('$_base/projects/$projectId/export?month=$month'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('Export failed (${res.statusCode})');
    return res.bodyBytes;
  }
}
