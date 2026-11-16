import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

const String kXlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

void downloadFileOnWeb(Uint8List bytes, String filename, {String mime = kXlsxMime}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..setAttribute('download', filename)
    ..click();
  web.URL.revokeObjectURL(url);
  anchor.remove();
}

/// Opens a new browser tab showing a file the API returns (a PDF, an image).
///
/// The tab is opened before [load] runs, while the click is still a user gesture,
/// so popup blockers allow it; it is closed again if loading fails.
Future<void> openInNewTab(Future<Uint8List> Function() load, String mime) async {
  final tab = web.window.open('', '_blank');
  try {
    final bytes = await load();
    final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime)));
    if (tab != null) {
      tab.location.href = url;
    } else if (web.window.open(url, '_blank') == null) {
      web.URL.revokeObjectURL(url);
      throw Exception('Your browser blocked the new tab. Allow pop-ups for this site, or use Download.');
    }
    // give the tab time to read the blob before releasing it
    Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  } catch (_) {
    tab?.close();
    rethrow;
  }
}
