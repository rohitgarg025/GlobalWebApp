import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/download_service.dart' show downloadFileOnWeb, openInNewTab;
import '../../services/drawing_api.dart';
import '../../services/project_api.dart';

const Color _kAccent = Color(0xFFB4450E);
const Color _kInk = Color(0xFF171A1C);
const Color _kMuted = Color(0xFF5B6168);
const Color _kLine = Color(0xFFDDE0DA);
const Color _kRowLine = Color(0xFFECEEEA);
const Color _kField = Color(0xFFCFD3CC);
const Color _kChipTrack = Color(0xFFF0F1EE);
const Color _kPill = Color(0xFF1B1F23);
const Color _kPillOld = Color(0xFFE6E8E3);
const Color _kSelected = Color(0xFFFFF4EC);
const Color _kHeadBg = Color(0xFFFAFAF8);
const Color _kError = Color(0xFFA21C1C);
const String _kMono = 'monospace';
const int _kMaxBytes = 100 * 1024 * 1024;
// table columns: fixed widths, the drawing name takes the rest (null)
const List<double?> _colWidth = [136, null, 84, 116, 124, 156];
const double _kNameMin = 180;
const double _kTableMin = 136 + _kNameMin + 84 + 116 + 124 + 156;
const double _kPanelWidth = 320;
const double _kGap = 16;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _date(DateTime? d) =>
    d == null ? '—' : '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

String _size(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String _errText(Object e) => e.toString().replaceFirst('Exception: ', '');

({Color bg, Color fg}) _fmtColors(String fmt) =>
    fmt == 'DWG' ? (bg: const Color(0xFFE3ECF8), fg: const Color(0xFF1E4E8C)) : (bg: const Color(0xFFFBE7E3), fg: const Color(0xFF9A2A16));

class DrawingRegisterScreen extends StatefulWidget {
  const DrawingRegisterScreen({super.key});

  @override
  State<DrawingRegisterScreen> createState() => _DrawingRegisterScreenState();
}

class _DrawingRegisterScreenState extends State<DrawingRegisterScreen> {
  List<Project> _projects = [];
  Project? _project;
  List<Drawing> _drawings = [];
  bool _loading = false;
  String? _error;
  int? _selectedId;

  final _search = TextEditingController();
  String _fmt = 'All';
  String _disc = 'All';

  final Map<int, Uint8List> _previews = {}; // revision id → PNG
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await ProjectApi.listProjects();
      if (mounted) setState(() => _projects = projects);
    } catch (_) {}
  }

  Future<void> _load() async {
    final project = _project;
    if (project == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await DrawingApi.list(project.id);
      if (!mounted || _project?.id != project.id) return;
      setState(() {
        _drawings = list;
        if (_selectedId == null || !list.any((d) => d.id == _selectedId)) {
          _selectedId = list.isEmpty ? null : list.first.id;
        }
      });
      _afterSelect();
    } catch (e) {
      if (mounted) setState(() => _error = _errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Drawing? get _selected {
    for (final d in _drawings) {
      if (d.id == _selectedId) return d;
    }
    return null;
  }

  List<Drawing> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _drawings.where((d) {
      if (_fmt != 'All' && d.current.fmt != _fmt) return false;
      if (_disc != 'All' && d.discipline != _disc) return false;
      if (q.isNotEmpty && !'${d.title} ${d.number}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  void _select(Drawing d) {
    setState(() => _selectedId = d.id);
    _afterSelect();
  }

  void _replace(Drawing d) {
    final i = _drawings.indexWhere((x) => x.id == d.id);
    setState(() {
      if (i >= 0) {
        _drawings[i] = d;
      } else {
        _drawings.insert(0, d);
      }
    });
  }

  /// Fetch the selected drawing's DWG preview, polling while the server renders it.
  void _afterSelect() {
    _poll?.cancel();
    final d = _selected;
    if (d == null) return;
    final cur = d.current;
    if (cur.previewStatus == 'ready' && !_previews.containsKey(cur.id)) {
      DrawingApi.previewBytes(cur.id).then((png) {
        if (mounted) setState(() => _previews[cur.id] = png);
      }).catchError((_) {});
    } else if (cur.previewStatus == 'pending') {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          final fresh = await DrawingApi.get(d.id);
          if (!mounted) return;
          if (fresh.current.previewStatus != 'pending') {
            _poll?.cancel();
            _replace(fresh);
            if (_selectedId == fresh.id) _afterSelect();
          }
        } catch (_) {}
      });
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _kError : _kPill,
      behavior: SnackBarBehavior.floating,
      width: 420,
    ));
  }

  Future<void> _download(Drawing d, DrawingRevision r) async {
    try {
      final bytes = await DrawingApi.fileBytes(r.id);
      downloadFileOnWeb(bytes, r.filename,
          mime: r.fmt == 'PDF' ? 'application/pdf' : 'application/octet-stream');
    } catch (e) {
      if (mounted) _toast(_errText(e), error: true);
    }
  }

  void _view(Drawing d) {
    final cur = d.current;
    if (cur.fmt == 'PDF') {
      openInNewTab(() => DrawingApi.fileBytes(cur.id), 'application/pdf')
          .catchError((Object e) => _toast(_errText(e), error: true));
      return;
    }
    switch (cur.previewStatus) {
      case 'ready':
        openInNewTab(() async => _previews[cur.id] ?? await DrawingApi.previewBytes(cur.id), 'image/png')
            .catchError((Object e) => _toast(_errText(e), error: true));
      case 'pending':
        _toast('The drawing picture is still being prepared — try again in a minute.');
      default:
        _toast('Preview not available — download to open in CAD.');
    }
  }

  Future<void> _openUpload({Drawing? revise}) async {
    final project = _project;
    if (project == null) return;
    final result = await showDialog<_UploadResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadDialog(
        projectId: project.id,
        drawings: _drawings,
        startAsRevision: revise != null,
        targetId: (revise ?? _selected)?.id,
      ),
    );
    if (result == null || !mounted) return;
    _replace(result.drawing);
    _select(result.drawing);
    final d = result.drawing;
    _toast(result.isNew ? '${d.number} uploaded as ${d.current.rev}' : '${d.number} updated to ${d.current.rev}');
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F4F1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.description, color: _kAccent, size: 22),
        ),
        const SizedBox(width: 12),
        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Drawing Register',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kInk)),
              Text('Latest revision of every drawing, with full history',
                  overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: _kMuted)),
            ],
          ),
        ),
      ],
    );
    final picker = _ProjectDropdown(
      projects: _projects,
      selected: _project,
      onChanged: (p) {
        _poll?.cancel();
        setState(() {
          _project = p;
          _drawings = [];
          _selectedId = null;
          _error = null;
        });
        _load();
      },
    );
    final upload = _project == null
        ? null
        : FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _kAccent,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _openUpload(),
            icon: const Icon(Icons.upload, size: 18),
            label: const Text('Upload drawing', style: TextStyle(fontWeight: FontWeight.w600)),
          );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 8),
              picker,
              if (upload != null) ...[const SizedBox(height: 8), upload],
            ],
          );
        }
        return Row(
          children: [
            Flexible(child: title),
            const SizedBox(width: 24),
            picker,
            const Spacer(),
            ?upload,
          ],
        );
      }),
    );
  }

  Widget _body() {
    if (_project == null) {
      return _Empty(
        title: 'No project selected',
        subtitle: _projects.isEmpty
            ? 'No projects yet. Ask an administrator to create a project.'
            : 'Select a project above to see its drawing register.',
      );
    }
    if (_loading && _drawings.isEmpty) return const Center(child: CircularProgressIndicator(color: _kAccent));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _kError)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_drawings.isEmpty) {
      return _Empty(
        title: 'No drawings yet',
        subtitle: 'Click "Upload drawing" to add the first PDF or DWG for ${_project!.name}.',
      );
    }

    final rows = _filtered;
    final sel = _selected;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth - 48 >= _kTableMin + _kGap + _kPanelWidth;
      final table = _table(rows);
      final panel = sel == null ? null : _DetailPanel(
        drawing: sel,
        preview: _previews[sel.current.id],
        onView: () => _view(sel),
        onDownload: (r) => _download(sel, r),
        onRevise: () => _openUpload(revise: sel),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(),
            const SizedBox(height: 20),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: table),
                  if (panel != null) ...[const SizedBox(width: _kGap), SizedBox(width: _kPanelWidth, child: panel)],
                ],
              )
            else ...[
              table,
              if (panel != null) ...[const SizedBox(height: 20), panel],
            ],
          ],
        ),
      );
    });
  }

  Widget _toolbar() {
    return _Card(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 480),
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 14),
                decoration: _inputDecoration('Search by drawing name or number…').copyWith(
                  prefixIcon: const Icon(Icons.search, size: 18, color: _kMuted),
                  fillColor: _kHeadBg,
                ),
              ),
            ),
          ),
          _Segmented(
            options: const ['All', 'PDF', 'DWG'],
            value: _fmt,
            onChanged: (v) => setState(() => _fmt = v),
          ),
          _SelectBox(
            value: _disc,
            items: {'All': 'All disciplines', for (final d in kDisciplines) d: d},
            onChanged: (v) => setState(() => _disc = v),
          ),
        ],
      ),
    );
  }

  Widget _table(List<Drawing> rows) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 4,
              children: [
                Text('Showing ${rows.length} of ${_drawings.length} drawings',
                    style: const TextStyle(fontSize: 13, color: _kMuted)),
                const Text('Latest revision shown · click a drawing for history',
                    style: TextStyle(fontSize: 13, color: _kMuted)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE6E8E3)),
          LayoutBuilder(builder: (context, c) {
            final width = c.maxWidth < _kTableMin ? _kTableMin : c.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    const _HeadRow(),
                    for (final d in rows)
                      _DrawingRow(
                        drawing: d,
                        selected: d.id == _selectedId,
                        onSelect: () => _select(d),
                        onView: () {
                          _select(d);
                          _view(d);
                        },
                        onDownload: () => _download(d, d.current),
                        onRevise: () => _openUpload(revise: d),
                      ),
                  ],
                ),
              ),
            );
          }),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
              child: Column(
                children: [
                  const Text('No drawings match your search',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _kInk)),
                  const SizedBox(height: 8),
                  const Text('Try a different name or number, or clear the filters.',
                      style: TextStyle(fontSize: 13, color: _kMuted)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _search.clear();
                      _fmt = 'All';
                      _disc = 'All';
                    }),
                    child: const Text('Clear filters'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Table ──────────────────────────────────────────────────────────────

Widget _cell(int i, Widget child) {
  final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: child);
  final w = _colWidth[i];
  return w == null ? Expanded(child: padded) : SizedBox(width: w, child: padded);
}

class _HeadRow extends StatelessWidget {
  const _HeadRow();

  @override
  Widget build(BuildContext context) {
    const labels = ['DRAWING NO.', 'DRAWING NAME', 'FORMAT', 'REVISION', 'LAST UPDATED', 'ACTIONS'];
    return Container(
      color: _kHeadBg,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            _cell(
              i,
              Text(labels[i],
                  maxLines: 1,
                  textAlign: i == labels.length - 1 ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: _kMuted, letterSpacing: 0.6)),
            ),
        ],
      ),
    );
  }
}

class _DrawingRow extends StatelessWidget {
  final Drawing drawing;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onView;
  final VoidCallback onDownload;
  final VoidCallback onRevise;

  const _DrawingRow({
    required this.drawing,
    required this.selected,
    required this.onSelect,
    required this.onView,
    required this.onDownload,
    required this.onRevise,
  });

  @override
  Widget build(BuildContext context) {
    final cur = drawing.current;
    final older = drawing.revisions.length - 1;
    return Material(
      color: selected ? _kSelected : Colors.white,
      child: InkWell(
        onTap: onSelect,
        hoverColor: _kHeadBg,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: const BorderSide(color: _kRowLine),
              left: BorderSide(color: selected ? _kAccent : Colors.transparent, width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              _cell(0, Text(drawing.number,
                  style: const TextStyle(fontFamily: _kMono, fontSize: 13, color: _kInk))),
              _cell(
                1,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(drawing.title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _kInk)),
                    const SizedBox(height: 2),
                    Text(drawing.discipline, style: const TextStyle(fontSize: 12, color: _kMuted)),
                  ],
                ),
              ),
              _cell(2, Align(alignment: Alignment.centerLeft, child: _FmtBadge(cur.fmt))),
              _cell(
                3,
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _RevPill(cur.rev),
                    Text(older == 0 ? 'First issue' : '$older earlier',
                        style: const TextStyle(fontSize: 12, color: _kMuted)),
                  ],
                ),
              ),
              _cell(
                4,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_date(cur.uploadedAt), style: const TextStyle(fontSize: 14, color: _kInk)),
                    const SizedBox(height: 2),
                    Text(cur.uploadedBy ?? '—',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _kMuted)),
                  ],
                ),
              ),
              _cell(
                5,
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _IconAction(Icons.visibility_outlined, 'View ${drawing.number}', onView),
                    _IconAction(Icons.download_outlined, 'Download ${drawing.number}', onDownload),
                    _IconAction(Icons.sync, 'Upload new revision of ${drawing.number}', onRevise),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Detail panel ───────────────────────────────────────────────────────

class _DetailPanel extends StatelessWidget {
  final Drawing drawing;
  final Uint8List? preview;
  final VoidCallback onView;
  final ValueChanged<DrawingRevision> onDownload;
  final VoidCallback onRevise;

  const _DetailPanel({
    required this.drawing,
    required this.preview,
    required this.onView,
    required this.onDownload,
    required this.onRevise,
  });

  @override
  Widget build(BuildContext context) {
    final cur = drawing.current;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(drawing.number, style: const TextStyle(fontFamily: _kMono, fontSize: 13, color: _kMuted)),
                const SizedBox(height: 6),
                Text(drawing.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _kInk)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _FmtBadge(cur.fmt),
                    _RevPill('${cur.rev} · Current'),
                    _Tag(drawing.discipline),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE6E8E3)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _preview(cur),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _PanelButton(icon: Icons.visibility_outlined, label: 'View', onPressed: onView)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PanelButton(
                          icon: Icons.download_outlined, label: 'Download', onPressed: () => onDownload(cur)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kAccent,
                      side: const BorderSide(color: _kAccent, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onRevise,
                    icon: const Icon(Icons.upload, size: 16),
                    label: Text('Upload revision ${drawing.nextRev}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Meta('File size', _size(cur.sizeBytes)),
                _Meta('Uploaded by', cur.uploadedBy ?? '—'),
                _Meta('Last updated', _date(cur.uploadedAt)),
                _Meta('Total revisions', '${drawing.revisions.length}'),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE6E8E3)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('REVISION HISTORY',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kMuted, letterSpacing: 0.6)),
                const SizedBox(height: 4),
                for (final r in drawing.revisions) _HistoryItem(rev: r, onDownload: () => onDownload(r)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(DrawingRevision cur) {
    Widget body;
    if (cur.fmt == 'DWG' && preview != null) {
      body = InkWell(
        onTap: onView,
        child: Image.memory(preview!, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      );
    } else if (cur.fmt == 'DWG' && cur.previewStatus == 'pending') {
      body = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent)),
            SizedBox(height: 10),
            Text('Preparing drawing picture…', style: TextStyle(fontSize: 12, color: _kMuted)),
          ],
        ),
      );
    } else if (cur.fmt == 'DWG' && cur.previewStatus == 'ready') {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent));
    } else {
      final pdf = cur.fmt == 'PDF';
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(pdf ? Icons.picture_as_pdf_outlined : Icons.image_not_supported_outlined,
                size: 32, color: _kMuted),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(pdf ? 'PDF · click View to open it in a new tab' : 'Preview not available — download to open in CAD',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: _kMuted)),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F5),
        border: Border.all(color: _kField),
        borderRadius: BorderRadius.circular(8),
      ),
      child: body,
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final DrawingRevision rev;
  final VoidCallback onDownload;

  const _HistoryItem({required this.rev, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final current = rev.isCurrent;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _kChipTrack))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: current ? _kPill : _kPillOld, borderRadius: BorderRadius.circular(4)),
            child: Text(rev.rev,
                style: TextStyle(
                    fontFamily: _kMono,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: current ? Colors.white : const Color(0xFF33393F))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rev.remarks ?? '—',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: current ? _kInk : _kMuted)),
                const SizedBox(height: 2),
                Text(
                  '${rev.uploadedBy ?? '—'} · ${_date(rev.uploadedAt)} · ${current ? 'Current' : 'Superseded'} · ${rev.fmt}',
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                ),
              ],
            ),
          ),
          _IconAction(Icons.download_outlined, 'Download revision ${rev.rev}', onDownload, size: 36),
        ],
      ),
    );
  }
}

// ─── Upload dialog ──────────────────────────────────────────────────────

class _UploadResult {
  final Drawing drawing;
  final bool isNew;
  const _UploadResult(this.drawing, this.isNew);
}

class _UploadDialog extends StatefulWidget {
  final int projectId;
  final List<Drawing> drawings;
  final bool startAsRevision;
  final int? targetId; // drawing pre-selected for "Revision of existing"

  const _UploadDialog({
    required this.projectId,
    required this.drawings,
    this.startAsRevision = false,
    this.targetId,
  });

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  late bool _isNew = !widget.startAsRevision || widget.drawings.isEmpty;
  late int? _targetId = widget.targetId ?? (widget.drawings.isEmpty ? null : widget.drawings.first.id);
  PlatformFile? _file;
  String? _fileError;
  final _number = TextEditingController();
  final _title = TextEditingController();
  final _remarks = TextEditingController();
  String _discipline = kDisciplines.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _title.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Drawing? get _target {
    for (final d in widget.drawings) {
      if (d.id == _targetId) return d;
    }
    return null;
  }

  bool get _canUpload =>
      !_busy &&
      _file != null &&
      _fileError == null &&
      (_isNew ? _number.text.trim().isNotEmpty && _title.text.trim().isNotEmpty : _target != null);

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'dwg'],
      withData: true,
    );
    final f = res?.files.single;
    if (f == null) return;
    final ext = f.name.split('.').last.toLowerCase();
    setState(() {
      _file = f;
      _fileError = ext != 'pdf' && ext != 'dwg'
          ? 'Only .pdf and .dwg files can be uploaded.'
          : f.size > _kMaxBytes
              ? 'This file is larger than 100 MB.'
              : null;
    });
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Drawing d;
      if (_isNew) {
        d = await DrawingApi.createDrawing(widget.projectId, _file!,
            number: _number.text.trim(),
            title: _title.text.trim(),
            discipline: _discipline,
            remarks: _remarks.text.trim());
      } else {
        d = await DrawingApi.addRevision(_target!.id, _file!, remarks: _remarks.text.trim());
      }
      if (mounted) Navigator.of(context).pop(_UploadResult(d, _isNew));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Upload drawing',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kInk)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE6E8E3)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Segmented(
                      options: const ['New drawing', 'Revision of existing'],
                      value: _isNew ? 'New drawing' : 'Revision of existing',
                      expand: true,
                      onChanged: (v) {
                        if (v == 'Revision of existing' && widget.drawings.isEmpty) return;
                        setState(() => _isNew = v == 'New drawing');
                      },
                    ),
                    const SizedBox(height: 18),
                    _dropZone(),
                    if (_fileError != null) ...[
                      const SizedBox(height: 8),
                      Text(_fileError!, style: const TextStyle(fontSize: 13, color: _kError)),
                    ],
                    const SizedBox(height: 18),
                    if (_isNew) ..._newFields() else if (target != null) ..._revisionFields(target),
                    const SizedBox(height: 18),
                    _label('Remarks', hint: ' (what changed)'),
                    TextField(
                      controller: _remarks,
                      minLines: 2,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 14),
                      decoration: _inputDecoration('e.g. Column C4 size revised to 450×600'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(fontSize: 13, color: _kError)),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE6E8E3)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kAccent,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    onPressed: _canUpload ? _upload : null,
                    child: _busy
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isNew || target == null ? 'Upload drawing' : 'Upload as ${target.nextRev}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropZone() {
    return InkWell(
      onTap: _busy ? null : _pick,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        decoration: BoxDecoration(
          color: _kHeadBg,
          border: Border.all(color: _fileError != null ? _kError : _kField, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            const Icon(Icons.upload_file, size: 28, color: _kMuted),
            const SizedBox(height: 8),
            Text(_file?.name ?? 'Choose a PDF or DWG file',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _kInk)),
            const SizedBox(height: 4),
            Text(_file == null ? 'Click to browse · PDF or DWG, up to 100 MB' : '${_size(_file!.size)} · click to change',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: _kMuted)),
          ],
        ),
      ),
    );
  }

  List<Widget> _newFields() => [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: 248,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label('Drawing number'),
                  TextField(
                    controller: _number,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: 14, fontFamily: _kMono),
                    decoration: _inputDecoration('e.g. GBE-TA-AR-108'),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 248,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label('Discipline'),
                  _SelectBox(
                    value: _discipline,
                    items: {for (final d in kDisciplines) d: d},
                    onChanged: (v) => setState(() => _discipline = v),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _label('Drawing name'),
        TextField(
          controller: _title,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 14),
          decoration: _inputDecoration('e.g. Fifth Floor Plan'),
        ),
      ];

  List<Widget> _revisionFields(Drawing target) => [
        _label('Drawing being revised'),
        _SelectBox(
          value: '${target.id}',
          items: {for (final d in widget.drawings) '${d.id}': '${d.number} — ${d.title} (${d.current.rev})'},
          onChanged: (v) => setState(() => _targetId = int.parse(v)),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _kSelected, borderRadius: BorderRadius.circular(8)),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RevPill(target.current.rev, old: true),
              const Icon(Icons.arrow_forward, size: 16, color: Color(0xFF33393F)),
              _RevPill(target.nextRev),
              Text('${target.current.rev} will be marked superseded and kept in history.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF33393F))),
            ],
          ),
        ),
      ];

  Widget _label(String text, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(
          text: text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kInk),
          children: [
            if (hint != null) TextSpan(text: hint, style: const TextStyle(fontWeight: FontWeight.w400, color: _kMuted)),
          ],
        )),
      );
}

// ─── Small pieces ───────────────────────────────────────────────────────

InputDecoration _inputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF8A9096)),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kField)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kField)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kAccent, width: 1.5)),
    );

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _Card({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kLine),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _Segmented extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final bool expand;

  const _Segmented({required this.options, required this.value, required this.onChanged, this.expand = false});

  @override
  Widget build(BuildContext context) {
    Widget seg(String o) {
      final on = o == value;
      return Semantics(
        selected: on,
        button: true,
        child: InkWell(
          onTap: () => onChanged(o),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 36,
            constraints: const BoxConstraints(minWidth: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              boxShadow: on ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 2, offset: Offset(0, 1))] : null,
            ),
            child: Text(o,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: on ? _kInk : const Color(0xFF4A5057))),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _kChipTrack, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            expand ? Expanded(child: seg(options[i])) : seg(options[i]),
          ],
        ],
      ),
    );
  }
}

class _SelectBox extends StatelessWidget {
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const _SelectBox({required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kField),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: false,
          style: const TextStyle(fontSize: 14, color: _kInk),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _FmtBadge extends StatelessWidget {
  final String fmt;
  const _FmtBadge(this.fmt);

  @override
  Widget build(BuildContext context) {
    final c = _fmtColors(fmt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(4)),
      child: Text(fmt,
          style: TextStyle(fontFamily: _kMono, fontSize: 12, fontWeight: FontWeight.w600, color: c.fg)),
    );
  }
}

class _RevPill extends StatelessWidget {
  final String text;
  final bool old;
  const _RevPill(this.text, {this.old = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: old ? _kPillOld : _kPill, borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(
              fontFamily: _kMono,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: old ? const Color(0xFF33393F) : Colors.white)),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _kChipTrack, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF33393F))),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;
  const _Meta(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: _kMuted)),
          const SizedBox(height: 2),
          Text(value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _kInk)),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  const _IconAction(this.icon, this.tooltip, this.onPressed, {this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 18,
        color: const Color(0xFF33393F),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _PanelButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _kInk,
          side: const BorderSide(color: _kField),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _ProjectDropdown extends StatelessWidget {
  final List<Project> projects;
  final Project? selected;
  final ValueChanged<Project?> onChanged;

  const _ProjectDropdown({required this.projects, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      child: DropdownButton<int?>(
        value: selected?.id,
        hint: Text(
          projects.isEmpty ? 'No projects' : 'Select project',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
        underline: const SizedBox(),
        isExpanded: true,
        items: projects
            .map((p) => DropdownMenuItem<int?>(
                  value: p.id,
                  child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                ))
            .toList(),
        onChanged: (id) {
          if (id == null) return;
          onChanged(projects.firstWhere((p) => p.id == id));
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Empty({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}
