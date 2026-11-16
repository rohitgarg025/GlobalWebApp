import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart' show ApiService;
import 'auth_service.dart';

const List<String> kDisciplines = ['Architectural', 'Structural', 'MEP', 'Civil'];

class DrawingRevision {
  final int id;
  final String rev; // R0, R1, …
  final int revNo;
  final String filename;
  final String fmt; // PDF | DWG
  final int sizeBytes;
  final String? remarks;
  final String? uploadedBy;
  final DateTime? uploadedAt;
  final String previewStatus; // none | pending | ready | failed
  final bool isCurrent;

  const DrawingRevision({
    required this.id,
    required this.rev,
    required this.revNo,
    required this.filename,
    required this.fmt,
    required this.sizeBytes,
    this.remarks,
    this.uploadedBy,
    this.uploadedAt,
    required this.previewStatus,
    required this.isCurrent,
  });

  factory DrawingRevision.fromJson(Map<String, dynamic> j) => DrawingRevision(
        id: j['id'] as int,
        rev: j['rev'] as String,
        revNo: j['rev_no'] as int,
        filename: j['filename'] as String,
        fmt: j['fmt'] as String,
        sizeBytes: j['size_bytes'] as int? ?? 0,
        remarks: j['remarks'] as String?,
        uploadedBy: j['uploaded_by'] as String?,
        // the API sends naive UTC timestamps
        uploadedAt: j['uploaded_at'] == null ? null : DateTime.parse('${j['uploaded_at']}Z').toLocal(),
        previewStatus: j['preview_status'] as String? ?? 'none',
        isCurrent: j['status'] == 'current',
      );
}

class Drawing {
  final int id;
  final String number;
  final String title;
  final String discipline;
  final List<DrawingRevision> revisions; // newest first

  DrawingRevision get current => revisions.first;
  String get nextRev => 'R${current.revNo + 1}';

  const Drawing({
    required this.id,
    required this.number,
    required this.title,
    required this.discipline,
    required this.revisions,
  });

  factory Drawing.fromJson(Map<String, dynamic> j) => Drawing(
        id: j['id'] as int,
        number: j['number'] as String,
        title: j['title'] as String,
        discipline: j['discipline'] as String,
        revisions: ((j['revisions'] as List?) ?? [])
            .map((e) => DrawingRevision.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DrawingApi {
  static String get _base => '${ApiService.baseUrl}/api/drawing-register';
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

  static Drawing _drawing(http.Response res) => Drawing.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

  static Future<List<Drawing>> list(int projectId) async {
    final res = await http
        .get(Uri.parse('$_base/projects/$projectId/drawings'), headers: _auth)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res, 'Could not load drawings');
    return (jsonDecode(res.body) as List).map((e) => Drawing.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Drawing> get(int drawingId) async {
    final res = await http.get(Uri.parse('$_base/drawings/$drawingId'), headers: _auth).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res, 'Could not load drawing');
    return _drawing(res);
  }

  static Future<Drawing> _upload(String path, PlatformFile file, Map<String, String> fields) async {
    final bytes = file.bytes;
    if (bytes == null) throw Exception('Could not read ${file.name}');
    final req = http.MultipartRequest('POST', Uri.parse('$_base$path'))
      ..headers.addAll(_auth)
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: file.name));
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 10)));
    if (res.statusCode != 201) _fail(res, 'Upload failed');
    return _drawing(res);
  }

  static Future<Drawing> createDrawing(int projectId, PlatformFile file,
          {required String number, required String title, required String discipline, String remarks = ''}) =>
      _upload('/projects/$projectId/drawings', file,
          {'number': number, 'title': title, 'discipline': discipline, 'remarks': remarks});

  static Future<Drawing> addRevision(int drawingId, PlatformFile file, {String remarks = ''}) =>
      _upload('/drawings/$drawingId/revisions', file, {'remarks': remarks});

  static Future<Uint8List> fileBytes(int revisionId) async {
    final res = await http
        .get(Uri.parse('$_base/revisions/$revisionId/file'), headers: _auth)
        .timeout(const Duration(minutes: 5));
    if (res.statusCode != 200) _fail(res, 'Download failed');
    return res.bodyBytes;
  }

  static Future<Uint8List> previewBytes(int revisionId) async {
    final res = await http
        .get(Uri.parse('$_base/revisions/$revisionId/preview'), headers: _auth)
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) _fail(res, 'Preview not available');
    return res.bodyBytes;
  }
}
