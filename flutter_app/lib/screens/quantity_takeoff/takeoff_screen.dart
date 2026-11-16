import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/download_service.dart' show downloadFileOnWeb;
import '../../services/takeoff_api.dart';

const Color _kBrand = Color(0xFF0066CC);
const Color _kError = Color(0xFFD32F2F);
const Color _kWarn = Color(0xFFB45309);
const Color _kInk = Color(0xFF1A1A2E);

const _kActivities = [
  ('concrete', 'Concrete (RCC)', 'm³', true),
  ('formwork', 'Formwork / Shuttering', 'm²', true),
  ('reinforcement', 'Reinforcement — coming soon', 'kg', false),
];

String _unitFor(String activity) =>
    _kActivities.firstWhere((a) => a.$1 == activity, orElse: () => _kActivities.first).$3;

class TakeoffScreen extends StatefulWidget {
  const TakeoffScreen({super.key});

  @override
  State<TakeoffScreen> createState() => _TakeoffScreenState();
}

class _TakeoffScreenState extends State<TakeoffScreen> {
  TakeoffJob? _job;
  List<TakeoffJob> _history = [];
  PlatformFile? _file;
  bool _uploading = false;
  String? _error;
  Timer? _poll;

  // Floor selection
  String? _floorLayout;
  String _activity = 'concrete';
  final _height = TextEditingController();
  final _slabThk = TextEditingController();

  // Review
  final Map<String, List<Map<String, dynamic>>> _rows = {};
  final Set<String> _dirty = {};
  bool _saving = false;
  bool _exporting = false;
  bool _showNotes = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _height.dispose();
    _slabThk.dispose();
    super.dispose();
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _loadHistory() async {
    try {
      final h = await TakeoffApi.list();
      if (mounted) setState(() => _history = h);
    } catch (_) {}
  }

  void _setJob(TakeoffJob job) {
    setState(() {
      _job = job;
      if (job.status == 'done') {
        _rows
          ..clear()
          ..addAll({for (final e in job.rows.entries) e.key: [...e.value]});
        _dirty.clear();
      }
      if (job.status == 'floors_ready' && _floorLayout == null && job.floors.isNotEmpty) {
        _floorLayout = job.floorLayout ?? job.floors.first.layout;
      }
    });
    _poll?.cancel();
    if (job.isWorking) {
      _poll = Timer(const Duration(seconds: 3), () async {
        try {
          final next = await TakeoffApi.get(job.id);
          if (mounted && _job?.id == job.id) _setJob(next);
        } catch (e) {
          if (mounted) setState(() => _error = _msg(e));
        }
      });
    } else {
      _loadHistory();
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['dwg', 'dxf'],
      withData: true,
    );
    if (r != null && r.files.isNotEmpty) {
      setState(() {
        _file = r.files.first;
        _error = null;
      });
    }
  }

  Future<void> _upload() async {
    final f = _file;
    if (f == null) return;
    if (f.size > 80 * 1024 * 1024) {
      setState(() => _error = 'Drawing is larger than 80 MB.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
      _floorLayout = null;
    });
    try {
      _setJob(await TakeoffApi.upload(f));
    } catch (e) {
      setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _analyse() async {
    final job = _job;
    if (job == null || _floorLayout == null) return;
    double? h;
    if (_height.text.trim().isNotEmpty) {
      h = double.tryParse(_height.text.trim());
      if (h == null || h < 2 || h > 12) {
        setState(() => _error = 'Floor height should be a number between 2 and 12 m.');
        return;
      }
    }
    int? thk;
    if (_slabThk.text.trim().isNotEmpty) {
      thk = int.tryParse(_slabThk.text.trim());
      if (thk == null || thk < 75 || thk > 500) {
        setState(() => _error = 'Default slab thickness should be a whole number between 75 and 500 mm.');
        return;
      }
    }
    setState(() => _error = null);
    try {
      _setJob(await TakeoffApi.analyse(job.id, _floorLayout!, h, defaultSlabMm: thk));
    } catch (e) {
      setState(() => _error = _msg(e));
    }
  }

  void _reset() {
    _poll?.cancel();
    setState(() {
      _job = null;
      _file = null;
      _error = null;
      _floorLayout = null;
      _rows.clear();
      _dirty.clear();
    });
    _loadHistory();
  }

  Future<void> _open(TakeoffJob j) async {
    try {
      final full = await TakeoffApi.get(j.id);
      _floorLayout = full.floorLayout;
      _setJob(full);
    } catch (e) {
      setState(() => _error = _msg(e));
    }
  }

  Future<bool> _save() async {
    final job = _job;
    if (job == null || _dirty.isEmpty) return true;
    setState(() => _saving = true);
    try {
      TakeoffJob latest = job;
      for (final a in [..._dirty]) {
        latest = await TakeoffApi.saveRows(job.id, a, _rows[a] ?? []);
      }
      _setJob(latest);
      return true;
    } catch (e) {
      setState(() => _error = _msg(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _download() async {
    final job = _job;
    if (job == null) return;
    setState(() => _exporting = true);
    try {
      if (!await _save()) return;
      final bytes = await TakeoffApi.export(job.id, _activity);
      final base = job.filename.replaceAll(RegExp(r'\.(dwg|dxf)$', caseSensitive: false), '');
      final name = 'MS_${base}_${job.floorTitle ?? ''}_$_activity'
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      downloadFileOnWeb(bytes, '$name.xlsx');
    } catch (e) {
      setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        if (_error != null) _ErrorBanner(message: _error!, onClose: () => setState(() => _error = null)),
        Expanded(
          child: job == null
              ? _uploadView()
              : job.status == 'done'
                  ? _reviewView(job)
                  : job.status == 'failed'
                      ? _failedView(job)
                      : job.status == 'floors_ready'
                          ? _floorView(job)
                          : _progressView(job),
        ),
      ],
    );
  }

  Widget _header() {
    final job = _job;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kBrand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.architecture, color: _kBrand, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quantity Takeoff',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kInk)),
                Text(
                  job == null
                      ? 'Upload a structural drawing (.dwg / .dxf) — Claude reads it, the app measures it'
                      : '${job.filename}${job.floorTitle != null ? ' · ${job.floorTitle}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (job != null)
            TextButton.icon(
              onPressed: job.isWorking ? null : _reset,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New drawing'),
            ),
        ],
      ),
    );
  }

  // ─── Upload ────────────────────────────────────────────────────────────────

  Widget _uploadView() {
    final f = _file;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('1. Upload drawing',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Structural framing / GFC drawing with one layout tab per floor. '
                    'DWG (AutoCAD 2018 or older) or DXF, up to 80 MB.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _uploading ? null : _pick,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                      decoration: BoxDecoration(
                        color: _kBrand.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kBrand.withValues(alpha: 0.35), width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Icon(f == null ? Icons.upload_file : Icons.insert_drive_file,
                              size: 36, color: _kBrand),
                          const SizedBox(height: 8),
                          Text(
                            f == null ? 'Click to choose a .dwg or .dxf file' : f.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          if (f != null)
                            Text('${(f.size / (1024 * 1024)).toStringAsFixed(1)} MB · click to change',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onPressed: f == null || _uploading ? null : _upload,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text(_uploading ? 'Uploading…' : 'Upload & read drawing'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Previous takeoffs',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final h in _history.take(15))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: _StatusDot(status: h.status),
                        title: Text(h.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            if (h.floorTitle != null) h.floorTitle!,
                            _statusLabel(h.status),
                            if (h.createdAt != null) _date(h.createdAt!),
                          ].join(' · '),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _open(h),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Floor selection ───────────────────────────────────────────────────────

  Widget _floorView(TakeoffJob job) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('2. Choose floor and activity',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(job.message ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  const Text('Floor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in job.floors)
                        ChoiceChip(
                          label: Text(f.title),
                          selected: _floorLayout == f.layout,
                          onSelected: (_) => setState(() => _floorLayout = f.layout),
                          selectedColor: _kBrand.withValues(alpha: 0.15),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _activity,
                          decoration: const InputDecoration(
                            labelText: 'Activity',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final a in _kActivities)
                              DropdownMenuItem(
                                value: a.$1,
                                enabled: a.$4,
                                child: Text('${a.$2}${a.$4 ? ' (${a.$3})' : ''}',
                                    style: TextStyle(color: a.$4 ? null : Colors.grey)),
                              ),
                          ],
                          onChanged: (v) => setState(() => _activity = v ?? 'concrete'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 230,
                        child: TextField(
                          controller: _height,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: const InputDecoration(
                            labelText: 'Floor-to-floor height (m)',
                            helperText: 'Optional — Claude looks for it in the drawing',
                            helperMaxLines: 2,
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 360,
                    child: TextField(
                      controller: _slabThk,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Default slab thickness (mm)',
                        helperText: 'Optional — used only where the drawing shows no thickness; '
                            'those rows are flagged for checking',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8FB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Beams and columns are measured from the drawing geometry; Claude lays out slab panels by '
                      'grid, resolves unclear labels and notes assumptions. Concrete and formwork are both '
                      'prepared — you can switch between them on the review screen. Takes 1–3 minutes.',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onPressed: _floorLayout == null ? null : _analyse,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Analyse floor'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Progress / failure ────────────────────────────────────────────────────

  Widget _progressView(TakeoffJob job) {
    final steps = [
      ('Upload', ['uploaded']),
      ('Convert & read drawing', ['converting']),
      ('Measure & Claude analysis', ['analysing']),
      ('Review', <String>[]),
    ];
    final current = steps.indexWhere((s) => s.$2.contains(job.status));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: i < current
                            ? const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20)
                            : i == current
                                ? const CircularProgressIndicator(strokeWidth: 2.5, color: _kBrand)
                                : Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(steps[i].$1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
                            color: i > current ? Colors.grey : _kInk,
                          )),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(job.message ?? 'Working…', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _failedView(TakeoffJob job) {
    final canRetry = job.floors.isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _kError, size: 36),
              const SizedBox(height: 8),
              const Text("Couldn't complete the takeoff",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(job.message ?? 'Unknown error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(onPressed: _reset, child: const Text('Try another drawing')),
                  if (canRetry) ...[
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _kBrand, foregroundColor: Colors.white),
                      onPressed: () => _setJob(TakeoffJob(
                        id: job.id,
                        filename: job.filename,
                        status: 'floors_ready',
                        message: 'Choose a floor to analyse.',
                        floors: job.floors,
                        floorLayout: job.floorLayout,
                        rows: const {},
                        summary: const {},
                        notes: const [],
                        missingInfo: const [],
                        conventions: const [],
                      )),
                      child: const Text('Choose floor again'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Review ────────────────────────────────────────────────────────────────

  Widget _reviewView(TakeoffJob job) {
    final rows = _rows[_activity] ?? [];
    final unit = _unitFor(_activity);
    final byType = <String, double>{};
    for (final r in rows) {
      final t = r['member_type'] == 'deduction' ? 'slab' : (r['member_type'] as String? ?? 'other');
      byType[t] = (byType[t] ?? 0) + _qty(r);
    }
    final total = byType.values.fold(0.0, (a, b) => a + b);
    final flagged = rows.where((r) => r['flag'] != null || r['confidence'] == 'low').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<String>(
                segments: [
                  for (final a in _kActivities.where((a) => a.$4))
                    ButtonSegment(value: a.$1, label: Text(a.$2)),
                ],
                selected: {_activity},
                onSelectionChanged: (s) => setState(() => _activity = s.first),
              ),
              for (final t in ['slab', 'beam', 'column'])
                if (byType.containsKey(t)) _TotalChip(label: '${_typeLabel(t)}s', value: byType[t]!, unit: unit),
              _TotalChip(label: 'Total', value: total, unit: unit, strong: true),
              if (flagged > 0)
                Chip(
                  avatar: const Icon(Icons.flag_outlined, size: 16, color: _kWarn),
                  label: Text('$flagged to check', style: const TextStyle(fontSize: 12, color: _kWarn)),
                  backgroundColor: _kWarn.withValues(alpha: 0.08),
                  side: BorderSide.none,
                ),
              OutlinedButton.icon(
                onPressed: _dirty.isEmpty || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_dirty.isEmpty ? 'Saved' : 'Save changes'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _kBrand, foregroundColor: Colors.white),
                onPressed: _exporting ? null : _download,
                icon: _exporting
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download measurement sheet'),
              ),
              TextButton(
                onPressed: () => _setJob(TakeoffJob(
                  id: job.id,
                  filename: job.filename,
                  status: 'floors_ready',
                  message: 'Choose another floor to analyse. The current results will be replaced.',
                  floors: job.floors,
                  floorLayout: job.floorLayout,
                  rows: const {},
                  summary: const {},
                  notes: const [],
                  missingInfo: const [],
                  conventions: const [],
                )),
                child: const Text('Analyse another floor'),
              ),
            ],
          ),
        ),
        _notesPanel(job),
        Expanded(child: _grid(rows, unit)),
      ],
    );
  }

  Widget _notesPanel(TakeoffJob job) {
    final s = job.summary;
    final warnings = ((s['warnings'] as List?) ?? []).cast<String>();
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showNotes = !_showNotes),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(_showNotes ? Icons.expand_less : Icons.expand_more, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Measured ${s['beams'] ?? 0} beam spans, ${s['columns'] ?? 0} columns, '
                      '${s['slab_panels'] ?? 0} slab panels · slab ${s['slab_thickness_mm'] ?? '?'} mm · '
                      'floor height ${s['floor_height_m'] ?? 'not found'}'
                      '${s['floor_height_m'] != null && s['height_source'] != null ? ' m (${s['height_source']})' : ''}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('Notes & assumptions', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),
          if (_showNotes)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(36, 0, 12, 10),
                children: [
                  for (final w in warnings) _NoteLine(text: w, color: _kWarn, icon: Icons.warning_amber),
                  for (final m in job.missingInfo) _NoteLine(text: m, color: _kWarn, icon: Icons.help_outline),
                  for (final n in job.notes) _NoteLine(text: n, color: Colors.black87, icon: Icons.notes),
                  for (final c in job.conventions)
                    _NoteLine(text: c, color: Colors.grey.shade600, icon: Icons.rule),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Nos × L × B × D. A blank dimension counts as 1 unless the row requires it
  /// (`req`), in which case the quantity is 0 — mirrors the server and the sheet.
  double _qty(Map<String, dynamic> r) {
    final req = (r['req'] as String?) ?? '';
    double q = (r['nos'] as num?)?.toDouble() ?? 0;
    for (final k in ['l', 'b', 'd']) {
      final v = r[k];
      if (v is num) {
        q *= v.toDouble();
      } else if (req.contains(k)) {
        return 0;
      }
    }
    return q;
  }

  void _edit(Map<String, dynamic> row, String field, String text) {
    final t = text.trim();
    if (['nos', 'l', 'b', 'd'].contains(field)) {
      row[field] = t.isEmpty ? null : double.tryParse(t);
    } else {
      row[field] = t;
    }
    row['flag'] = null; // edited by a person → no longer an automatic flag
    setState(() => _dirty.add(_activity));
  }

  void _addRow(String type) {
    final rows = _rows[_activity] ??= [];
    rows.add({
      'id': 'U${DateTime.now().millisecondsSinceEpoch}',
      'member_type': type,
      'mark': '',
      'location': '',
      'description': 'Added manually',
      'nos': 1.0,
      'l': null,
      'b': null,
      'd': null,
      'confidence': 'high',
      'remarks': 'added in review',
      'flag': null,
    });
    setState(() => _dirty.add(_activity));
  }

  void _deleteRow(Map<String, dynamic> row) {
    _rows[_activity]?.remove(row);
    setState(() => _dirty.add(_activity));
  }

  Widget _grid(List<Map<String, dynamic>> rows, String unit) {
    const order = ['slab', 'deduction', 'beam', 'column', 'other'];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final t = r['member_type'] == 'deduction' ? 'slab' : (r['member_type'] as String? ?? 'other');
      groups.putIfAbsent(order.contains(t) ? t : 'other', () => []).add(r);
    }
    final items = <Widget>[];
    for (final t in ['slab', 'beam', 'column', 'other']) {
      final g = groups[t];
      items.add(_GroupHeader(
        label: '${_typeLabel(t).toUpperCase()}S',
        total: g == null ? 0 : g.fold(0.0, (a, r) => a + _qty(r)),
        unit: unit,
        onAdd: () => _addRow(t),
      ));
      for (final r in g ?? const <Map<String, dynamic>>[]) {
        items.add(_RowEditor(
          key: ValueKey('$_activity-${r['id']}'),
          row: r,
          qty: _qty(r),
          onEdit: (f, v) => _edit(r, f, v),
          onDelete: () => _deleteRow(r),
        ));
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: LayoutBuilder(
        builder: (ctx, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: c.maxWidth < _RowEditor.width ? _RowEditor.width : c.maxWidth,
            child: Column(
              children: [
                const _GridHeader(),
                Expanded(child: ListView(children: items)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Small widgets ────────────────────────────────────────────────────────────

String _typeLabel(String t) => switch (t) {
      'slab' => 'Slab',
      'beam' => 'Beam',
      'column' => 'Column',
      'deduction' => 'Deduction',
      _ => 'Other',
    };

String _statusLabel(String s) => switch (s) {
      'done' => 'Ready',
      'failed' => 'Failed',
      'floors_ready' => 'Choose floor',
      'analysing' => 'Analysing',
      _ => 'Processing',
    };

String _date(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _fmt(num? v, {int dp = 3}) {
  if (v == null) return '';
  final s = v.toStringAsFixed(dp);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: child,
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _ErrorBanner({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) => Container(
        color: _kError.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: _kError, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(color: _kError, fontSize: 13))),
            IconButton(icon: const Icon(Icons.close, size: 16, color: _kError), onPressed: onClose),
          ],
        ),
      );
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = switch (status) {
      'done' => const Color(0xFF16A34A),
      'failed' => _kError,
      'floors_ready' => _kBrand,
      _ => _kWarn,
    };
    return Icon(Icons.circle, size: 10, color: c);
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final bool strong;
  const _TotalChip({required this.label, required this.value, required this.unit, this.strong = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: strong ? _kBrand.withValues(alpha: 0.1) : const Color(0xFFF3F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$label  ', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          TextSpan(
            text: '${value.toStringAsFixed(2)} $unit',
            style: TextStyle(
                fontSize: strong ? 14 : 13, fontWeight: FontWeight.w700, color: strong ? _kBrand : _kInk),
          ),
        ])),
      );
}

class _NoteLine extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _NoteLine({required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, height: 1.3))),
          ],
        ),
      );
}

// Grid columns: Mark, Location, Description, Nos, L, B, D/H, Qty, confidence, actions
const _cols = <(String, double)>[
  ('MARK', 110), ('LOCATION', 150), ('DESCRIPTION', 300), ('NOS', 64),
  ('L (m)', 80), ('B (m)', 80), ('D/H (m)', 80), ('QTY', 96), ('', 110),
];

class _GridHeader extends StatelessWidget {
  const _GridHeader();

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            for (final c in _cols)
              SizedBox(
                width: c.$2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(c.$1,
                      textAlign: ['NOS', 'L (m)', 'B (m)', 'D/H (m)', 'QTY'].contains(c.$1)
                          ? TextAlign.right
                          : TextAlign.left,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.4)),
                ),
              ),
          ],
        ),
      );
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final double total;
  final String unit;
  final VoidCallback onAdd;
  const _GroupHeader({required this.label, required this.total, required this.unit, required this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        color: const Color(0xFFEFF3F9),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kInk)),
            const SizedBox(width: 12),
            Text('${total.toStringAsFixed(3)} $unit',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kBrand)),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add row', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
}

class _RowEditor extends StatelessWidget {
  static final double width = _cols.fold(0.0, (a, c) => a + c.$2);

  final Map<String, dynamic> row;
  final double qty;
  final void Function(String field, String value) onEdit;
  final VoidCallback onDelete;

  const _RowEditor({
    super.key,
    required this.row,
    required this.qty,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final flag = row['flag'] as String?;
    final conf = row['confidence'] as String? ?? 'high';
    final deduction = row['member_type'] == 'deduction' || ((row['nos'] as num?) ?? 0) < 0;
    final warn = flag != null || conf == 'low';
    final remarks = [
      if (flag != null) flag,
      'Confidence: $conf',
      if ((row['remarks'] as String?)?.isNotEmpty ?? false) row['remarks'] as String,
    ].join('\n');

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFFF7EB) : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          _cell(0, row['mark'], 'mark'),
          _cell(1, row['location'], 'location'),
          _cell(2, row['description'], 'description', italic: deduction),
          _cell(3, _fmt(row['nos'] as num?, dp: 0), 'nos', numeric: true),
          _cell(4, _fmt(row['l'] as num?), 'l', numeric: true),
          _cell(5, _fmt(row['b'] as num?), 'b', numeric: true),
          _cell(6, _fmt(row['d'] as num?), 'd', numeric: true),
          SizedBox(
            width: _cols[7].$2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(qty.toStringAsFixed(3),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: deduction ? _kError : _kInk)),
            ),
          ),
          SizedBox(
            width: _cols[8].$2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Tooltip(
                  message: remarks,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (warn ? _kWarn : conf == 'medium' ? _kBrand : const Color(0xFF16A34A))
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (flag != null) const Icon(Icons.flag, size: 11, color: _kWarn),
                        Text(
                          flag != null ? ' check' : conf,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: warn ? _kWarn : conf == 'medium' ? _kBrand : const Color(0xFF16A34A)),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete row',
                  icon: const Icon(Icons.delete_outline, size: 16, color: _kError),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(int col, Object? value, String field, {bool numeric = false, bool italic = false}) {
    return SizedBox(
      width: _cols[col].$2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextFormField(
          initialValue: value?.toString() ?? '',
          textAlign: numeric ? TextAlign.right : TextAlign.left,
          keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
          inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))] : null,
          style: TextStyle(fontSize: 12, fontStyle: italic ? FontStyle.italic : null),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          ),
          onChanged: (v) => onEdit(field, v),
        ),
      ),
    );
  }
}
