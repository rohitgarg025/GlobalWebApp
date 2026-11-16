import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart' show ApiService;
import 'auth_service.dart';

class BbsJob {
  final int id;
  final String filename;
  final String status; // uploaded, reading, needs_settings, computing, done, failed
  final String? message;
  final String? createdAt;
  final Map<String, dynamic> notes;
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> lines;
  final List<String> issues;
  final Map<String, dynamic> plans; // dia → plan
  final Map<String, dynamic> summary;

  bool get isWorking => status == 'uploaded' || status == 'reading' || status == 'computing';

  const BbsJob({
    required this.id,
    required this.filename,
    required this.status,
    this.message,
    this.createdAt,
    required this.notes,
    required this.settings,
    required this.lines,
    required this.issues,
    required this.plans,
    required this.summary,
  });

  factory BbsJob.fromJson(Map<String, dynamic> j) => BbsJob(
        id: j['id'] as int,
        filename: j['filename'] as String,
        status: j['status'] as String,
        message: j['message'] as String?,
        createdAt: j['created_at'] as String?,
        notes: Map<String, dynamic>.from(j['notes'] as Map? ?? {}),
        settings: Map<String, dynamic>.from(j['settings'] as Map? ?? {}),
        lines: ((j['lines'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        issues: ((j['issues'] as List?) ?? []).cast<String>(),
        plans: Map<String, dynamic>.from(j['plans'] as Map? ?? {}),
        summary: Map<String, dynamic>.from(j['summary'] as Map? ?? {}),
      );
}

class BbsApi {
  static String get _base => '${ApiService.baseUrl}/api/bbs';
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

  static BbsJob _job(http.Response res) => BbsJob.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

  static Future<BbsJob> upload(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) throw Exception('Could not read ${file.name}');
    final req = http.MultipartRequest('POST', Uri.parse('$_base/jobs'))
      ..headers.addAll(_auth)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: file.name));
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 10)));
    if (res.statusCode != 201 && res.statusCode != 200) _fail(res, 'Upload failed');
    return _job(res);
  }

  static Future<BbsJob> get(int id) async {
    final res = await http.get(Uri.parse('$_base/jobs/$id'), headers: _auth).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) _fail(res, 'Could not load BBS');
    return _job(res);
  }

  static Future<List<BbsJob>> list() async {
    final res = await http.get(Uri.parse('$_base/jobs'), headers: _auth).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res, 'Could not load list');
    return (jsonDecode(res.body) as List).map((e) => BbsJob.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<BbsJob> compute(int id, Map<String, dynamic> settings) async {
    final res = await http
        .post(Uri.parse('$_base/jobs/$id/compute'),
            headers: {'Content-Type': 'application/json', ..._auth}, body: jsonEncode(settings))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res, 'Could not start');
    return _job(res);
  }

  static Future<BbsJob> saveLines(int id, List<Map<String, dynamic>> lines) async {
    final res = await http
        .put(Uri.parse('$_base/jobs/$id/lines'),
            headers: {'Content-Type': 'application/json', ..._auth}, body: jsonEncode({'lines': lines}))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) _fail(res, 'Could not save');
    return _job(res);
  }

  static Future<Uint8List> export(int id) async {
    final res = await http.get(Uri.parse('$_base/jobs/$id/export'), headers: _auth).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) _fail(res, 'Export failed');
    return res.bodyBytes;
  }
}
