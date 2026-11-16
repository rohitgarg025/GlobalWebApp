import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart' show ApiService;
import 'auth_service.dart';

class ReleaseSection {
  final String heading;
  final List<String> points;
  const ReleaseSection(this.heading, this.points);
}

class ReleaseNote {
  final DateTime? date; // null = in the code, not deployed yet
  final String title;
  final String area;
  final String summary;
  final List<ReleaseSection> sections;

  const ReleaseNote({this.date, required this.title, required this.area, required this.summary, required this.sections});

  factory ReleaseNote.fromJson(Map<String, dynamic> j) => ReleaseNote(
        date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
        title: j['title'] as String,
        area: j['area'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        sections: ((j['sections'] as List?) ?? [])
            .map((s) => ReleaseSection(
                  s['heading'] as String? ?? '',
                  ((s['points'] as List?) ?? []).map((p) => p.toString()).toList(),
                ))
            .toList(),
      );
}

class ReleaseNotesApi {
  static Future<List<ReleaseNote>> list() async {
    final res = await http
        .get(Uri.parse('${ApiService.baseUrl}/api/release-notes'), headers: AuthService.authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 401) AuthService.handleUnauthorized();
    if (res.statusCode != 200) {
      String detail = 'Could not load version history (${res.statusCode})';
      try {
        final err = jsonDecode(res.body);
        if (err is Map && err['detail'] != null) detail = err['detail'].toString();
      } catch (_) {}
      throw Exception(detail);
    }
    return (jsonDecode(res.body) as List).map((e) => ReleaseNote.fromJson(e as Map<String, dynamic>)).toList();
  }
}
