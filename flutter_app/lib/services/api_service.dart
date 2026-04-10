import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

import '../models/report_type.dart';
import '../models/output_file.dart';

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:8765',
  );

  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<ReportType>> fetchReportTypes() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/report-types'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch report types: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['report_types'] as List;
    return list.map((e) => ReportType.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<GenerateReportResult> generateReport({
    required String reportTypeId,
    required List<PlatformFile> files,
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl/api/reports/generate');
    final request = http.MultipartRequest('POST', uri);

    request.fields['report_type_id'] = reportTypeId;

    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null) throw Exception('Could not read file: ${file.name}');
      request.files.add(http.MultipartFile.fromBytes(
        'files',
        bytes,
        filename: file.name,
      ));
    }

    final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      String detail = 'Report generation failed.';
      try {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        detail = err['detail']?.toString() ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }

    return GenerateReportResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Uint8List> downloadFile(String fileId) async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/reports/download/$fileId'))
        .timeout(const Duration(minutes: 2));

    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<void> cleanupSession(String jobId) async {
    try {
      await http
          .delete(Uri.parse('$baseUrl/api/reports/session/$jobId'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort cleanup
    }
  }
}
