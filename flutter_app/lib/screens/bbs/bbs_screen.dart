import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/bbs_api.dart';
import '../../services/download_service.dart' show downloadFileOnWeb;

const Color _kBrand = Color(0xFF0066CC);
const Color _kError = Color(0xFFD32F2F);
const Color _kWarn = Color(0xFFB45309);
const Color _kOk = Color(0xFF16A34A);
const Color _kInk = Color(0xFF1A1A2E);
const _kDias = [8, 10, 12, 16, 20, 25, 28, 32];

class BbsScreen extends StatefulWidget {
  const BbsScreen({super.key});

  @override
  State<BbsScreen> createState() => _BbsScreenState();
}

class _BbsScreenState extends State<BbsScreen> {
  BbsJob? _job;
  List<BbsJob> _history = [];
  PlatformFile? _file;
  bool _busy = false;
  String? _error;
  Timer? _poll;

  // settings form
  final _lap = TextEditingController();
  final _cover = TextEditingController();
  final _stock = TextEditingController(text: '12');
  final _reuse = TextEditingController(text: '1.0');
  final _mult = TextEditingController(text: '1');
  final Map<int, TextEditingController> _stockPerDia = {};
  final Map<int, TextEditingController> _offcuts = {};

  // review
  List<Map<String, dynamic>> _lines = [];
  bool _dirty = false;
  int _tab = 0;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in [_lap, _cover, _stock, _reuse, _mult, ..._stockPerDia.values, ..._offcuts.values]) {
      c.dispose();
    }
    super.dispose();
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _loadHistory() async {
    try {
      final h = await BbsApi.list();
      if (mounted) setState(() => _history = h);
    } catch (_) {}
  }

  void _setJob(BbsJob job) {
    setState(() {
      final firstSettings = _job?.id != job.id || _job?.status != job.status;
      _job = job;
      if (job.status == 'needs_settings' && firstSettings) _fillSettings(job.settings);
      if (job.status == 'done') {
        _lines = job.lines.map((e) => Map<String, dynamic>.from(e)).toList();
        _dirty = false;
      }
    });
    _poll?.cancel();
    if (job.isWorking) {
      _poll = Timer(const Duration(seconds: 3), () async {
        try {
          final next = await BbsApi.get(job.id);
          if (mounted && _job?.id == job.id) _setJob(next);
        } catch (e) {
          if (mounted) setState(() => _error = _msg(e));
        }
      });
    } else {
      _loadHistory();
    }
  }

  void _fillSettings(Map<String, dynamic> s) {
    _lap.text = s['lap_factor']?.toString() ?? '';
    _cover.text = s['cover_beam_mm']?.toString() ?? '';
    _stock.text = ((s['default_stock_mm'] ?? 12000) / 1000).toString().replaceFirst(RegExp(r'\.0$'), '');
    _reuse.text = ((s['min_reuse_mm'] ?? 1000) / 1000).toString();
    _mult.text = (s['multiplier'] ?? 1).toString();
    final per = Map<String, dynamic>.from(s['stock_mm'] as Map? ?? {});
    final offs = Map<String, dynamic>.from(s['offcuts_mm'] as Map? ?? {});
    for (final d in _kDias) {
      (_stockPerDia[d] ??= TextEditingController()).text =
          per['$d'] != null ? ((per['$d'] as num) / 1000).toString() : '';
      (_offcuts[d] ??= TextEditingController()).text =
          ((offs['$d'] as List?) ?? []).map((e) => ((e as num) / 1000).toString()).join(', ');
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['dwg', 'dxf'],
      withData: true,
    );
    if (r != null && r.files.isNotEmpty) setState(() => _file = r.files.first);
  }

  Future<void> _upload() async {
    final f = _file;
    if (f == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _setJob(await BbsApi.upload(f));
    } catch (e) {
      setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compute() async {
    final job = _job;
    if (job == null) return;
    int? toInt(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());
    double? toD(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());
    final lap = toInt(_lap.text);
    final cover = toInt(_cover.text);
    if (lap == null || cover == null) {
      setState(() => _error = 'Enter the lap factor and the beam cover — the drawing doesn\'t fix them for you.');
      return;
    }
    final stock = toD(_stock.text) ?? 12;
    final perDia = <String, int>{};
    final offcuts = <String, List<int>>{};
    for (final d in _kDias) {
      final v = toD(_stockPerDia[d]?.text ?? '');
      if (v != null) perDia['$d'] = (v * 1000).round();
      final pieces = (_offcuts[d]?.text ?? '')
          .split(RegExp(r'[,\s]+'))
          .map((e) => double.tryParse(e))
          .whereType<double>()
          .map((m) => (m * 1000).round())
          .where((mm) => mm > 0)
          .toList();
      if (pieces.isNotEmpty) offcuts['$d'] = pieces;
    }
    setState(() => _error = null);
    try {
      _setJob(await BbsApi.compute(job.id, {
        'lap_factor': lap,
        'cover_beam_mm': cover,
        'default_stock_mm': (stock * 1000).round(),
        'stock_mm': perDia,
        'min_reuse_mm': ((toD(_reuse.text) ?? 1) * 1000).round(),
        'offcuts_mm': offcuts,
        'multiplier': toInt(_mult.text) ?? 1,
      }));
    } catch (e) {
      setState(() => _error = _msg(e));
    }
  }

  Future<void> _saveLines() async {
    final job = _job;
    if (job == null) return;
    try {
      _setJob(await BbsApi.saveLines(job.id, _lines));
    } catch (e) {
      setState(() => _error = _msg(e));
    }
  }

  Future<void> _download() async {
    final job = _job;
    if (job == null) return;
    if (_dirty) {
      setState(() => _error = 'Save your edits first — the cutting plan is recalculated from them.');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await BbsApi.export(job.id);
      final base = job.filename.replaceAll(RegExp(r'\.(dwg|dxf)$', caseSensitive: false), '');
      downloadFileOnWeb(bytes, 'BBS_${base.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.xlsx');
    } catch (e) {
      setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    _poll?.cancel();
    setState(() {
      _job = null;
      _file = null;
      _error = null;
      _lines = [];
      _dirty = false;
    });
    _loadHistory();
  }

  // ─── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        if (_error != null)
          Container(
            color: _kError.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(children: [
              const Icon(Icons.error_outline, color: _kError, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: const TextStyle(color: _kError, fontSize: 13))),
              IconButton(
                  icon: const Icon(Icons.close, size: 16, color: _kError),
                  onPressed: () => setState(() => _error = null)),
            ]),
          ),
        Expanded(
          child: job == null
              ? _uploadView()
              : job.status == 'failed'
                  ? _failed(job)
                  : job.status == 'needs_settings'
                      ? _settingsView(job)
                      : job.status == 'done'
                          ? _results(job)
                          : _progress(job),
        ),
      ],
    );
  }

  Widget _header() {
    final job = _job;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: _kBrand.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.straighten, color: _kBrand, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Bar Bending Schedule',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kInk)),
            Text(
              job == null
                  ? 'Upload a reinforcement drawing → IS 2502 BBS + optimised cutting plan (12 m bars)'
                  : job.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ]),
        ),
        if (job != null)
          TextButton.icon(
              onPressed: job.isWorking ? null : _reset,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New drawing')),
      ]),
    );
  }

  Widget _card(Widget child, {double maxWidth = 760}) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
            child: child,
          ),
        ),
      );

  Widget _uploadView() {
    final f = _file;
    return ListView(padding: const EdgeInsets.all(24), children: [
      _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Upload reinforcement drawing', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Beam details drawn in elevation with bar callouts (e.g. "2-12# Cont.", "+3-16# Extra") and stirrup '
          'zones (e.g. "#8@200c/c"). DWG or DXF, up to 80 MB. Columns and slabs are coming next.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _busy ? null : _pick,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: _kBrand.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBrand.withValues(alpha: 0.35), width: 1.5),
            ),
            child: Column(children: [
              Icon(f == null ? Icons.upload_file : Icons.insert_drive_file, size: 36, color: _kBrand),
              const SizedBox(height: 8),
              Text(f == null ? 'Click to choose a .dwg or .dxf file' : f.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              if (f != null)
                Text('${(f.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _kBrand, foregroundColor: Colors.white),
            onPressed: f == null || _busy ? null : _upload,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(_busy ? 'Uploading…' : 'Upload & read drawing'),
          ),
        ),
      ])),
      if (_history.isNotEmpty) ...[
        const SizedBox(height: 20),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Previous schedules', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          for (final h in _history.take(15))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.circle,
                  size: 10, color: h.status == 'done' ? _kOk : h.status == 'failed' ? _kError : _kWarn),
              title: Text(h.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(h.status.replaceAll('_', ' '), style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () async {
                try {
                  _setJob(await BbsApi.get(h.id));
                } catch (e) {
                  setState(() => _error = _msg(e));
                }
              },
            ),
        ])),
      ],
    ]);
  }

  Widget _progress(BbsJob job) => Center(
        child: _card(
          Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: _kBrand)),
            const SizedBox(height: 14),
            Text(job.message ?? 'Working…', textAlign: TextAlign.center),
          ]),
          maxWidth: 480,
        ),
      );

  Widget _failed(BbsJob job) => Center(
        child: _card(
          Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: _kError, size: 36),
            const SizedBox(height: 8),
            Text(job.message ?? 'Failed', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reset, child: const Text('Try another drawing')),
          ]),
          maxWidth: 520,
        ),
      );

  // ─── settings ──────────────────────────────────────────────────────────────

  Widget _settingsView(BbsJob job) {
    final n = job.notes;
    final lapTable = Map<String, dynamic>.from(n['lap_table'] as Map? ?? {});
    final covers = Map<String, dynamic>.from(n['covers_mm'] as Map? ?? {});
    final issues = ((n['issues'] as List?) ?? []).cast<String>();
    return ListView(padding: const EdgeInsets.all(24), children: [
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('What the drawing notes say', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(job.message ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        _kv('Steel', n['steel_grade'] ?? 'not stated'),
        _kv('Concrete', n['concrete_grade'] ?? 'not stated'),
        _kv('Lap table (${n['lap_table_label'] ?? 'lap'})',
            lapTable.isEmpty ? 'not found' : lapTable.entries.map((e) => '${e.key} → ${e.value}Ø').join('   ')),
        _kv('Clear covers',
            covers.isEmpty ? 'not found' : covers.entries.map((e) => '${e.key} ${e.value} mm').join('   ')),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final i in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber, size: 15, color: _kWarn),
                const SizedBox(width: 6),
                Expanded(child: Text(i, style: const TextStyle(fontSize: 12, color: _kWarn))),
              ]),
            ),
        ],
      ])),
      const SizedBox(height: 16),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Confirm settings', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Laps and covers come only from the drawing. Where it is silent or ambiguous, you decide.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
            width: 230,
            child: _num(_lap, 'Lap length (× Ø) *',
                helper: lapTable.isEmpty ? 'Enter from notes' : 'e.g. ${lapTable.values.first} from the table'),
          ),
          if (lapTable.isNotEmpty)
            Wrap(spacing: 6, children: [
              for (final e in lapTable.entries)
                ActionChip(
                  label: Text('${e.key}: ${e.value}Ø', style: const TextStyle(fontSize: 12)),
                  onPressed: () => setState(() => _lap.text = '${e.value}'),
                ),
            ]),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: 230, child: _num(_cover, 'Beam clear cover (mm) *', helper: 'Not in the notes → enter')),
          SizedBox(width: 180, child: _num(_stock, 'Stock bar length (m)', decimal: true)),
          SizedBox(width: 200, child: _num(_reuse, 'Reusable offcut ≥ (m)', decimal: true)),
          SizedBox(
              width: 230,
              child: _num(_mult, 'No. of identical blocks',
                  helper: 'e.g. 2 if the drawing is typical for two wings')),
        ]),
        const SizedBox(height: 14),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Per-diameter stock length and existing site offcuts (optional)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          children: [
            for (final d in _kDias)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(width: 60, child: Text('$d mm', style: const TextStyle(fontWeight: FontWeight.w600))),
                  SizedBox(
                      width: 150,
                      child: _num(_stockPerDia[d] ??= TextEditingController(), 'Stock (m)', decimal: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _offcuts[d] ??= TextEditingController(),
                      decoration: const InputDecoration(
                        labelText: 'Offcuts on site (m), comma separated',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _kBrand, foregroundColor: Colors.white),
            onPressed: _compute,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Build BBS & cutting plan'),
          ),
        ),
      ])),
    ]);
  }

  Widget _kv(String k, Object v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(k, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: Text('$v', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _num(TextEditingController c, String label, {String? helper, bool decimal = false}) => TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]'))],
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );

  // ─── results ───────────────────────────────────────────────────────────────

  Widget _results(BbsJob job) {
    final s = job.summary;
    final bars = (s['bars_to_buy'] as num?)?.toInt() ?? 0;
    final uncut = (s['uncut_bars'] as num?)?.toInt() ?? 0;
    final saved = uncut > 0 ? (100 * (uncut - bars) / uncut) : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _stat('Steel required', '${s['total_mt']} MT'),
          _stat('To purchase', '${s['purchase_mt']} MT'),
          _stat('12 m bars', '$bars (vs $uncut uncut)'),
          _stat('Bars saved', '${saved.toStringAsFixed(1)}%', good: true),
          if ((s['flagged'] ?? 0) > 0) _stat('Lines to check', '${s['flagged']}', warn: true),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _job = BbsJob(
                id: job.id, filename: job.filename, status: 'needs_settings', message: 'Change settings and rebuild.',
                notes: job.notes, settings: job.settings, lines: const [], issues: const [], plans: const {},
                summary: const {},
              );
              _fillSettings(job.settings);
            }),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Settings'),
          ),
          OutlinedButton.icon(
            onPressed: _dirty ? _saveLines : null,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_dirty ? 'Save & re-optimise' : 'Saved'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _kBrand, foregroundColor: Colors.white),
            onPressed: _busy ? null : _download,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Download Excel'),
          ),
        ]),
      ),
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(children: [
          for (final t in [('BBS (${_lines.length})', 0), ('Cutting plan', 1), ('Summary', 2), ('Issues (${job.issues.length})', 3)])
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(t.$1),
                selected: _tab == t.$2,
                onSelected: (_) => setState(() => _tab = t.$2),
                selectedColor: _kBrand.withValues(alpha: 0.15),
              ),
            ),
          const Spacer(),
          if (_tab == 0)
            SizedBox(
              width: 240,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Filter by member / mark',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: switch (_tab) {
          0 => _bbsGrid(),
          1 => _cuttingPlan(job),
          2 => _summary(job),
          _ => _issues(job),
        },
      ),
    ]);
  }

  Widget _stat(String label, String value, {bool good = false, bool warn = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (good ? _kOk : warn ? _kWarn : _kBrand).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: good ? _kOk : warn ? _kWarn : _kInk)),
        ]),
      );

  static const _cols = <(String, double)>[
    ('MARK', 90), ('MEMBER', 190), ('DESCRIPTION', 200), ('DIA', 56), ('SHAPE', 56), ('LEGS (mm)', 170),
    ('CUT (mm)', 80), ('NOS', 56), ('MEMB.', 56), ('LAPS', 50), ('KG', 80), ('', 70),
  ];

  Widget _bbsGrid() {
    final rows = _lines
        .where((l) =>
            _filter.isEmpty ||
            '${l['mark']} ${l['member']}'.toLowerCase().contains(_filter))
        .toList();
    final width = _cols.fold(0.0, (a, c) => a + c.$2);
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: LayoutBuilder(
        builder: (ctx, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: c.maxWidth < width ? width : c.maxWidth,
            child: Column(children: [
              Container(
                height: 34,
                color: Colors.grey.shade50,
                child: Row(children: [
                  for (final col in _cols)
                    SizedBox(
                      width: col.$2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(col.$1,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey)),
                      ),
                    ),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  itemExtent: 38,
                  itemCount: rows.length,
                  itemBuilder: (ctx, i) => _lineRow(rows[i]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _lineRow(Map<String, dynamic> l) {
    final flags = ((l['flags'] as List?) ?? []).cast<String>();
    final warn = flags.isNotEmpty || l['confidence'] == 'low';
    final legs = ((l['legs'] as List?) ?? []).map((e) => (e as num).round()).join(' + ');
    Widget txt(String s, double w, {FontWeight? fw}) => SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: fw)),
          ),
        );
    Widget edit(String field, double w) => SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: TextFormField(
              key: ValueKey('${l['mark']}-$field'),
              initialValue: '${l[field] ?? ''}',
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
              onChanged: (v) {
                l[field] = field == 'cut_length' ? double.tryParse(v) : int.tryParse(v);
                setState(() => _dirty = true);
              },
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFFF7EB) : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(children: [
        txt('${l['mark']}', _cols[0].$2, fw: FontWeight.w600),
        txt('${l['member']}', _cols[1].$2),
        txt('${l['description']}', _cols[2].$2),
        edit('dia', _cols[3].$2),
        Tooltip(message: '${l['shape']}', child: txt('${l['shape_code']}', _cols[4].$2)),
        txt(legs, _cols[5].$2),
        edit('cut_length', _cols[6].$2),
        edit('nos_per_member', _cols[7].$2),
        edit('members', _cols[8].$2),
        txt('${l['laps_per_bar']}', _cols[9].$2),
        txt(((l['weight_kg'] as num?) ?? 0).toStringAsFixed(1), _cols[10].$2, fw: FontWeight.w700),
        SizedBox(
          width: _cols[11].$2,
          child: Row(children: [
            Tooltip(
              message: [...flags, 'Confidence: ${l['confidence']}', '${l['evidence'] ?? ''}'].join('\n'),
              child: Icon(warn ? Icons.flag : Icons.check_circle_outline,
                  size: 16, color: warn ? _kWarn : _kOk),
            ),
            IconButton(
              tooltip: 'Delete line',
              icon: const Icon(Icons.delete_outline, size: 16, color: _kError),
              onPressed: () => setState(() {
                _lines.remove(l);
                _dirty = true;
              }),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _cuttingPlan(BbsJob job) {
    final entries = job.plans.entries.toList()..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));
    return ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 16), children: [
      for (final e in entries) _diaPlan(int.parse(e.key), Map<String, dynamic>.from(e.value as Map)),
    ]);
  }

  Widget _diaPlan(int dia, Map<String, dynamic> p) {
    final pats = ((p['patterns'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: ExpansionTile(
        initiallyExpanded: dia == 12,
        title: Text('$dia mm — ${p['new_bars']} bars of ${(p['stock_length'] ?? 12000) / 1000} m'
            '${(p['offcuts_used'] ?? 0) > 0 ? ' + ${p['offcuts_used']} site offcuts' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
          'Scrap ${p['wastage_pct']}% (without plan: ${p['baseline_bars']} bars, ${p['baseline_wastage_pct']}% scrap) · '
          'reusable offcuts ${p['reusable_m']} m · ${p['method']}',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          for (final pat in pats)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: _kBrand.withValues(alpha: 0.1),
                child: Text('×${pat['repeat']}', style: const TextStyle(fontSize: 11, color: _kBrand)),
              ),
              title: _barPicture(pat),
              subtitle: Text(
                '${_cutText(pat)} · leftover ${pat['leftover']} mm (${pat['leftover_kind']})',
                style: TextStyle(fontSize: 11, color: pat['leftover_kind'] == 'scrap' ? _kWarn : _kOk),
              ),
            ),
        ],
      ),
    );
  }

  String _cutText(Map<String, dynamic> pat) {
    final c = <int, int>{};
    for (final x in (pat['cuts'] as List)) {
      c[(x as num).toInt()] = (c[(x).toInt()] ?? 0) + 1;
    }
    final keys = c.keys.toList()..sort((a, b) => b.compareTo(a));
    return '${pat['source'] == 'offcut' ? 'Offcut ' : ''}${pat['stock_length']} mm → ${keys.map((k) => '${c[k]} × $k').join(' + ')}';
  }

  /// A proportional sketch of one stock bar and its cuts.
  Widget _barPicture(Map<String, dynamic> pat) {
    final total = (pat['stock_length'] as num).toDouble();
    final cuts = (pat['cuts'] as List).map((e) => (e as num).toDouble()).toList();
    final left = (pat['leftover'] as num).toDouble();
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth.clamp(200.0, 900.0);
      return Row(children: [
        for (final x in cuts)
          Container(
            width: w * x / total,
            height: 16,
            margin: const EdgeInsets.only(right: 1),
            color: _kBrand.withValues(alpha: 0.75),
            alignment: Alignment.center,
            child: w * x / total > 34
                ? Text('${x.round()}', style: const TextStyle(fontSize: 9, color: Colors.white))
                : null,
          ),
        if (left > 0)
          Container(
            width: (w * left / total).clamp(1.0, w),
            height: 16,
            color: pat['leftover_kind'] == 'scrap' ? _kWarn.withValues(alpha: 0.5) : _kOk.withValues(alpha: 0.5),
          ),
      ]);
    });
  }

  Widget _summary(BbsJob job) {
    final rows = ((job.summary['by_dia'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 16), children: [
      Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
        child: DataTable(columns: const [
          DataColumn(label: Text('Dia')),
          DataColumn(label: Text('Required (kg)'), numeric: true),
          DataColumn(label: Text('Bars to buy'), numeric: true),
          DataColumn(label: Text('Purchase (kg)'), numeric: true),
          DataColumn(label: Text('Scrap %'), numeric: true),
          DataColumn(label: Text('Without plan: bars / scrap %'), numeric: true),
          DataColumn(label: Text('Reusable offcuts (m)'), numeric: true),
        ], rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text('${r['dia']} mm')),
              DataCell(Text(((r['weight_kg'] as num?) ?? 0).toStringAsFixed(1))),
              DataCell(Text('${r['bars_to_buy']}')),
              DataCell(Text('${r['purchase_kg']}')),
              DataCell(Text('${r['wastage_pct']}')),
              DataCell(Text('${r['uncut_bars']} / ${r['uncut_wastage_pct']}')),
              DataCell(Text('${r['reusable_m']}')),
            ]),
        ]),
      ),
    ]);
  }

  Widget _issues(BbsJob job) {
    final noteIssues = ((job.notes['issues'] as List?) ?? []).cast<String>();
    return ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 16), children: [
      for (final i in [...noteIssues, ...job.issues])
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber, size: 15, color: _kWarn),
            const SizedBox(width: 6),
            Expanded(child: Text(i, style: const TextStyle(fontSize: 12))),
          ]),
        ),
      if (noteIssues.isEmpty && job.issues.isEmpty) const Text('No issues.'),
    ]);
  }
}
