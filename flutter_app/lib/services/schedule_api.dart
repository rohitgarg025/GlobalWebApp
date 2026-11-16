import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_service.dart' show ApiService;
import 'auth_service.dart';

class PmActivity {
  final int id;
  final int projectId;
  final String name;
  final String code;
  final int durationDays;
  final String startDate;
  final String finishDate;
  final String startMode;
  final int? predecessorId;
  final int lagDays;
  final double? quantity;
  final String? unit;
  final int sortOrder;
  final String? createdBy;
  final String rowType; // activity | group
  final int? parentId;
  final int? floorId;
  final String? floorName;

  bool get isGroup => rowType == 'group';

  const PmActivity({
    required this.id,
    required this.projectId,
    required this.name,
    required this.code,
    required this.durationDays,
    required this.startDate,
    required this.finishDate,
    required this.startMode,
    this.predecessorId,
    required this.lagDays,
    this.quantity,
    this.unit,
    required this.sortOrder,
    this.createdBy,
    this.rowType = 'activity',
    this.parentId,
    this.floorId,
    this.floorName,
  });

  factory PmActivity.fromJson(Map<String, dynamic> j) => PmActivity(
        id: j['id'] as int,
        projectId: j['project_id'] as int,
        name: j['name'] as String,
        code: j['code'] as String,
        durationDays: j['duration_days'] as int,
        startDate: j['start_date'] as String,
        finishDate: j['finish_date'] as String,
        startMode: j['start_mode'] as String? ?? 'manual',
        predecessorId: j['predecessor_id'] as int?,
        lagDays: j['lag_days'] as int? ?? 0,
        quantity: (j['quantity'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
        sortOrder: j['sort_order'] as int? ?? 0,
        createdBy: j['created_by'] as String?,
        rowType: j['row_type'] as String? ?? 'activity',
        parentId: j['parent_id'] as int?,
        floorId: j['floor_id'] as int?,
        floorName: j['floor_name'] as String?,
      );
}

class ScheduleApi {
  static String get _base => '${ApiService.baseUrl}/api/project-schedule';
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
    int successCode = 201,
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

  static Future<List<PmActivity>> getSchedule(int projectId) =>
      _get('/projects/$projectId/schedule',
          (j) => ((j as Map)['activities'] as List)
              .map((e) => PmActivity.fromJson(e as Map<String, dynamic>))
              .toList());

  static Future<PmActivity> createActivity({
    required int projectId,
    required String name,
    String rowType = 'activity',
    int? durationDays,
    String? startDate,
    int? parentId,
    int? floorId,
    int? predecessorId,
    int lagDays = 0,
    double? quantity,
    String? unit,
  }) =>
      _post(
        '/projects/$projectId/activities',
        {
          'name': name,
          'row_type': rowType,
          if (durationDays != null) 'duration_days': durationDays,
          if (startDate != null) 'start_date': startDate,
          if (parentId != null) 'parent_id': parentId,
          if (floorId != null) 'floor_id': floorId,
          if (predecessorId != null) 'predecessor_id': predecessorId,
          'lag_days': lagDays,
          if (quantity != null) 'quantity': quantity,
          if (unit != null && unit.isNotEmpty) 'unit': unit,
        },
        (j) => PmActivity.fromJson(j as Map<String, dynamic>),
      );

  static Future<PmActivity> updateActivity(
    int activityId, {
    String? name,
    int? durationDays,
    String? startDate,
    int? predecessorId,
    bool clearPredecessor = false,
    int? lagDays,
    double? quantity,
    bool clearQuantity = false,
    String? unit,
    int? parentId,
    bool clearParent = false,
    int? floorId,
  }) =>
      _patch(
        '/activities/$activityId',
        {
          if (name != null) 'name': name,
          if (durationDays != null) 'duration_days': durationDays,
          if (startDate != null) 'start_date': startDate,
          if (predecessorId != null) 'predecessor_id': predecessorId,
          if (clearPredecessor) 'clear_predecessor': true,
          if (lagDays != null) 'lag_days': lagDays,
          if (quantity != null) 'quantity': quantity,
          if (clearQuantity) 'clear_quantity': true,
          if (unit != null) 'unit': unit,
          if (parentId != null) 'parent_id': parentId,
          if (clearParent) 'clear_parent': true,
          if (floorId != null) 'floor_id': floorId,
        },
        (j) => PmActivity.fromJson(j as Map<String, dynamic>),
      );

  static Future<void> deleteActivity(int activityId) => _delete('/activities/$activityId');

  /// Sets the order of rows that share one parent group.
  static Future<void> reorderSiblings(int projectId, List<int> activityIds) async {
    final res = await http
        .put(
          Uri.parse('$_base/projects/$projectId/activities/reorder'),
          headers: {'Content-Type': 'application/json', ..._auth},
          body: jsonEncode({'activity_ids': activityIds}),
        )
        .timeout(const Duration(seconds: 15));
    _check401(res);
    if (res.statusCode != 200) {
      String detail = 'Reorder failed (${res.statusCode})';
      try {
        final err = jsonDecode(res.body);
        if (err is Map && err['detail'] != null) detail = err['detail'].toString();
      } catch (_) {}
      throw Exception(detail);
    }
  }

  static Future<Uint8List> exportExcel(int projectId) async {
    final res = await http
        .get(Uri.parse('$_base/projects/$projectId/schedule/export'), headers: _auth)
        .timeout(const Duration(seconds: 30));
    _check401(res);
    if (res.statusCode != 200) throw Exception('Export failed (${res.statusCode})');
    return res.bodyBytes;
  }
}
