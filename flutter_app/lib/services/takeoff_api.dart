import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart' show ApiService;
import 'auth_service.dart';

class TakeoffFloor {
  final String layout;
  final String title;
  const TakeoffFloor(this.layout, this.title);
}

class TakeoffJob {
  final int id;
  final String filename;
  final String status; // uploaded, converting, floors_ready, analysing, done, failed
  final String? message;
  final List<TakeoffFloor> floors;
  final String? floorLayout;
  final String? floorTitle;
  final double? floorHeightM;
  final String? createdAt;
  final String? createdBy;

  /// activity → measurement rows (plain maps so the grid can edit them in place)
  final Map<String, List<Map<String, dynamic>>> rows;
  final Map<String, dynamic> summary;
  final List<String> notes;
  final List<String> missingInfo;
  final List<String> conventions;
  final int inputTokens;
  final int outputTokens;

  bool get isWorking => status == 'uploaded' || status == 'converting' || status == 'analysing';

  const TakeoffJob({
    required this.id,
    required this.filename,
    required this.status,
    this.message,
    required this.floors,
    this.floorLayout,
    this.floorTitle,
    this.floorHeightM,
    this.createdAt,
    this.createdBy,
    required this.rows,
    required this.summary,
    required this.notes,
    required this.missingInfo,
    required this.conventions,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  factory TakeoffJob.fromJson(Map<String, dynamic> j) {
    final rows = <String, List<Map<String, dynamic>>>{};
    (j['rows'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      rows[k] = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
    final ai = j['ai'] as Map<String, dynamic>? ?? {};
    final usage = j['usage'] as Map<String, dynamic>? ?? {};
    return TakeoffJob(
      id: j['id'] as int,
      filename: j['filename'] as String,
      status: j['status'] as String,
      message: j['message'] as String?,
      floors: ((j['floors'] as List?) ?? [])
          .map((f) => TakeoffFloor(f['layout'] as String, f['title'] as String))
          .toList(),
      floorLayout: j['floor_layout'] as String?,
      floorTitle: j['floor_title'] as String?,
      floorHeightM: (j['floor_height_m'] as num?)?.toDouble(),
      createdAt: j['created_at'] as String?,
      createdBy: j['created_by'] as String?,
      rows: rows,
      summary: Map<String, dynamic>.from(j['summary'] as Map? ?? {}),
      notes: ((ai['notes'] as List?) ?? []).cast<String>(),
      missingInfo: ((ai['missing_info'] as List?) ?? []).cast<String>(),
      conventions: ((j['conventions'] as List?) ?? []).cast<String>(),
      inputTokens: usage['input_tokens'] as int? ?? 0,
      outputTokens: usage['output_tokens'] as int? ?? 0,
    );
  }
}

class TakeoffApi {
  static String get _base => '${ApiService.baseUrl}/api/quantity-takeoff';
  static Map<String, String> get _auth => AuthService.authHeaders;

  static Never _fail(http.Response res, String fallback) {
    if (res.statusCode == 401) AuthService.handleUnauthorized();
    String detail = '$fallback (${res.statusCode})';
    try {
      final err = jsonDecode(res.body);
      if (err is Map && err['detail'] != null) detail = err['detail'].toString();
    } catch (_) {}
    throw Exception(detail);
  }

  static Future<TakeoffJob> upload(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) throw Exception('Could not read ${file.name}');
    final req = http.MultipartRequest('POST', Uri.parse('$_base/jobs'))
      ..headers.addAll(_auth)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: file.name));
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(minutes: 10)));
    if (res.statusCode != 201 && res.statusCode != 200) _fail(res, 'Upload failed');
    return TakeoffJob.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<TakeoffJob> get(int id) async {
    final res = await http
        .get(Uri.parse('$_base/jobs/$id'), headers: _auth)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res, 'Could not load takeoff');
    return TakeoffJob.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<List<TakeoffJob>> list() async {
    final res = await http
        .get(Uri.parse('$_base/jobs'), headers: _auth)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res, 'Could not load takeoffs');
    return (jsonDecode(res.body) as List)
        .map((e) => TakeoffJob.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<TakeoffJob> analyse(int id, String floorLayout, double? floorHeightM,
      {int? defaultSlabMm}) async {
    final res = await http
        .post(
          Uri.parse('$_base/jobs/$id/analyse'),
          headers: {'Content-Type': 'application/json', ..._auth},
          body: jsonEncode({
            'floor_layout': floorLayout,
            if (floorHeightM != null) 'floor_height_m': floorHeightM,
            if (defaultSlabMm != null) 'default_slab_mm': defaultSlabMm,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res, 'Could not start analysis');
    return TakeoffJob.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<TakeoffJob> saveRows(int id, String activity, List<Map<String, dynamic>> rows) async {
    final res = await http
        .put(
          Uri.parse('$_base/jobs/$id/rows'),
          headers: {'Content-Type': 'application/json', ..._auth},
          body: jsonEncode({'activity': activity, 'rows': rows}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) _fail(res, 'Could not save rows');
    return TakeoffJob.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<Uint8List> export(int id, String activity) async {
    final res = await http
        .get(Uri.parse('$_base/jobs/$id/export?activity=$activity'), headers: _auth)
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) _fail(res, 'Export failed');
    return res.bodyBytes;
  }

  static Future<void> delete(int id) async {
    final res = await http
        .delete(Uri.parse('$_base/jobs/$id'), headers: _auth)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 204 && res.statusCode != 200) _fail(res, 'Delete failed');
  }
}
