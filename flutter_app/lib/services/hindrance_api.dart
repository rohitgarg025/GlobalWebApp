import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart' show ApiService;
import 'auth_service.dart';

class Hindrance {
  final int id;
  final int projectId;
  final int? activityId;
  final String? activityCode;
  final String? activityName;
  final String? raisedOn;
  final String type;
  final String description;
  final String? startDate;
  final String? endDate;
  final int? delayDays;
  final String status;
  final String? remarks;
  final String? raisedBy;

  const Hindrance({
    required this.id,
    required this.projectId,
    this.activityId,
    this.activityCode,
    this.activityName,
    this.raisedOn,
    required this.type,
    required this.description,
    this.startDate,
    this.endDate,
    this.delayDays,
    required this.status,
    this.remarks,
    this.raisedBy,
  });

  factory Hindrance.fromJson(Map<String, dynamic> j) => Hindrance(
        id: j['id'] as int,
        projectId: j['project_id'] as int,
        activityId: j['activity_id'] as int?,
        activityCode: j['activity_code'] as String?,
        activityName: j['activity_name'] as String?,
        raisedOn: j['raised_on'] as String?,
        type: j['type'] as String,
        description: j['description'] as String,
        startDate: j['start_date'] as String?,
        endDate: j['end_date'] as String?,
        delayDays: j['delay_days'] as int?,
        status: j['status'] as String? ?? 'open',
        remarks: j['remarks'] as String?,
        raisedBy: j['raised_by'] as String?,
      );
}

class ActivityOption {
  final int id;
  final String name;
  final String code;

  const ActivityOption({required this.id, required this.name, required this.code});

  factory ActivityOption.fromJson(Map<String, dynamic> j) => ActivityOption(
        id: j['id'] as int,
        name: j['name'] as String,
        code: j['code'] as String,
      );
}

class HindranceApi {
  static String get _base => '${ApiService.baseUrl}/api/hindrance-register';
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
  }

  static Future<List<Hindrance>> listHindrances(int projectId) =>
      _get('/projects/$projectId/hindrances',
          (j) => (j as List).map((e) => Hindrance.fromJson(e as Map<String, dynamic>)).toList());

  static Future<List<ActivityOption>> activityOptions(int projectId) =>
      _get('/projects/$projectId/activity-options',
          (j) => (j as List)
              .map((e) => ActivityOption.fromJson(e as Map<String, dynamic>))
              .toList());

  static Future<Hindrance> createHindrance({
    required int projectId,
    String? raisedOn,
    required String type,
    required String description,
    int? activityId,
    String? startDate,
    String? endDate,
    int? delayDays,
    String status = 'open',
    String? remarks,
  }) =>
      _post(
        '/projects/$projectId/hindrances',
        {
          if (raisedOn != null) 'raised_on': raisedOn,
          'type': type,
          'description': description,
          if (activityId != null) 'activity_id': activityId,
          if (startDate != null) 'start_date': startDate,
          if (endDate != null) 'end_date': endDate,
          if (delayDays != null) 'delay_days': delayDays,
          'status': status,
          if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        },
        (j) => Hindrance.fromJson(j as Map<String, dynamic>),
      );

  static Future<Hindrance> updateHindrance(
    int hindranceId, {
    String? raisedOn,
    String? type,
    String? description,
    int? activityId,
    bool clearActivity = false,
    String? startDate,
    String? endDate,
    int? delayDays,
    String? status,
    String? remarks,
  }) =>
      _patch(
        '/hindrances/$hindranceId',
        {
          if (raisedOn != null) 'raised_on': raisedOn,
          if (type != null) 'type': type,
          if (description != null) 'description': description,
          if (activityId != null) 'activity_id': activityId,
          if (clearActivity) 'clear_activity': true,
          if (startDate != null) 'start_date': startDate,
          if (endDate != null) 'end_date': endDate,
          if (delayDays != null) 'delay_days': delayDays,
          if (status != null) 'status': status,
          if (remarks != null) 'remarks': remarks,
        },
        (j) => Hindrance.fromJson(j as Map<String, dynamic>),
      );

  static Future<void> deleteHindrance(int hindranceId) => _delete('/hindrances/$hindranceId');
}
