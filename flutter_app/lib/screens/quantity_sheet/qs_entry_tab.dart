import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/quantity_sheet/qs_models.dart';
import '../../services/quantity_sheet_api.dart';
import 'qs_widgets.dart';

// ── Layout constants ──────────────────────────────────────────────────────────
const double _kRowHeaderW = 220.0;
const double _kUnitW = 60.0;
const double _kCellW = 110.0;
const double _kRowH = 40.0;
const double _kHeaderH = 56.0;
const double _kSubHeaderH = 36.0;

class QsEntryTab extends StatefulWidget {
  const QsEntryTab({super.key});

  @override
  State<QsEntryTab> createState() => _QsEntryTabState();
}

class _QsEntryTabState extends State<QsEntryTab> {
  List<Map<String, dynamic>> _projects = [];
  int? _projectId;
  String _month = _currentMonth();
  QsProjectData? _data;
  bool _loading = false;
  String? _error;

  // Grid state: key=(activityId, floorId), value=[totalEst, estActual, actual]
  final Map<String, List<TextEditingController>> _ctrl = {};
  final Map<String, List<FocusNode>> _focus = {};
  // Which total_est cells have been modified from baseline (need change reason)
  final Map<String, String> _changeReasons = {}; // key → reason
  // Justifications per (activityId, floorId)
  final Map<String, String> _justifications = {};

  String? _submittedBy;
  bool _submitting = false;
  String? _submitError;
  String? _submitSuccess;

  final ScrollController _hScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    for (final list in _ctrl.values) {
      for (final c in list) { c.dispose(); }
    }
    for (final list in _focus.values) {
      for (final f in list) { f.dispose(); }
    }
    super.dispose();
  }

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  String _cellKey(int actId, int floorId) => '$actId:$floorId';

  Future<void> _loadProjects() async {
    try {
      final projects = await QsApi.listProjects();
      if (mounted) {
        setState(() {
          _projects = projects
              .map((p) => <String, dynamic>{'id': p.id, 'name': p.name})
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    if (_projectId == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _submitSuccess = null;
      _submitError = null;
    });
    try {
      final data = await QsApi.getProjectData(_projectId!, _month);
      _initGrid(data);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _initGrid(QsProjectData data) {
    // Dispose old controllers
    for (final list in _ctrl.values) {
      for (final c in list) { c.dispose(); }
    }
    for (final list in _focus.values) {
      for (final f in list) { f.dispose(); }
    }
    _ctrl.clear();
    _focus.clear();
    _changeReasons.clear();
    _justifications.clear();

    for (final act in data.activities) {
      for (final floor in data.floors) {
        final key = _cellKey(act.id, floor.id);
        final cell = data.cell(act.id, floor.id);
        _ctrl[key] = [
          TextEditingController(
              text: _fmt(cell?.totalEstimatedQty)),
          TextEditingController(
              text: _fmt(cell?.estimateActualQtyTillDate)),
          TextEditingController(text: _fmt(cell?.actualQty)),
        ];
        _focus[key] = List.generate(3, (_) => FocusNode());
        if (cell?.justification != null && cell!.justification!.isNotEmpty) {
          _justifications[key] = cell.justification!;
        }
      }
    }
  }

  String _fmt(double? v) => v == null ? '' : v.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');

  double? _parse(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  // ── Clipboard paste (Excel TSV) ───────────────────────────────────────────

  Future<void> _pasteFromClipboard() async {
    final raw = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (raw == null || raw.isEmpty || _data == null) return;

    final lines = raw.trimRight().split('\n');
    // If it's a multi-cell block (contains tabs), distribute across grid
    // Grid column order: for each floor: [totalEst, estActual, actual]
    // Grid row order: activities
    final acts = _data!.activities;
    final floors = _data!.floors;

    if (lines.length > 1 || lines[0].contains('\t')) {
      // Multi-cell paste: rows=activities, cols=floors×3
      for (int r = 0; r < lines.length && r < acts.length; r++) {
        final cols = lines[r].split('\t');
        for (int c = 0; c < cols.length; c++) {
          final floorIdx = c ~/ 3;
          final subCol = c % 3;
          if (floorIdx >= floors.length) break;
          final key = _cellKey(acts[r].id, floors[floorIdx].id);
          final val = cols[c].trim();
          if (val.isNotEmpty && _ctrl.containsKey(key)) {
            _ctrl[key]![subCol].text = val;
          }
        }
      }
      setState(() {});
      _showSnack('Pasted ${lines.length} row(s) from clipboard');
    }
  }

  void _copyToClipboard() {
    if (_data == null) return;
    final buf = StringBuffer();
    for (final act in _data!.activities) {
      final parts = <String>[];
      for (final floor in _data!.floors) {
        final key = _cellKey(act.id, floor.id);
        final ctrl = _ctrl[key];
        if (ctrl != null) {
          parts.addAll([ctrl[0].text, ctrl[1].text, ctrl[2].text]);
        }
      }
      buf.writeln(parts.join('\t'));
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    _showSnack('Grid copied to clipboard (Excel-compatible TSV)');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ── Validation & submit ───────────────────────────────────────────────────

  bool _hasOverrun(int actId, int floorId) {
    final key = _cellKey(actId, floorId);
    final ctrl = _ctrl[key];
    if (ctrl == null) return false;
    final totalEst = _parse(ctrl[0].text);
    final actual = _parse(ctrl[2].text);
    if (totalEst == null || actual == null) return false;
    return actual > totalEst;
  }

  List<(String, int, int)> _collectOverrunCells() {
    if (_data == null) return [];
    final result = <(String, int, int)>[];
    for (final act in _data!.activities) {
      for (final floor in _data!.floors) {
        if (_hasOverrun(act.id, floor.id)) {
          final key = _cellKey(act.id, floor.id);
          if ((_justifications[key] ?? '').isEmpty) {
            result.add(('${act.name} / ${floor.name}', act.id, floor.id));
          }
        }
      }
    }
    return result;
  }

  List<(String, int, int)> _collectBaselineChanges() {
    if (_data == null) return [];
    final result = <(String, int, int)>[];
    for (final act in _data!.activities) {
      for (final floor in _data!.floors) {
        final cell = _data!.cell(act.id, floor.id);
        if (cell?.baselineLocked != true) continue;
        final key = _cellKey(act.id, floor.id);
        final newVal = _parse(_ctrl[key]?[0].text ?? '');
        final oldVal = cell?.totalEstimatedQty;
        if (newVal != null && oldVal != null && (newVal - oldVal).abs() > 1e-9) {
          if ((_changeReasons[key] ?? '').isEmpty) {
            result.add(('${act.name} / ${floor.name}', act.id, floor.id));
          }
        }
      }
    }
    return result;
  }

  Future<void> _submit() async {
    if (_data == null) return;

    // Collect overruns needing justification
    final overruns = _collectOverrunCells();
    if (overruns.isNotEmpty) {
      final confirmed = await _showJustificationDialog(overruns);
      if (!confirmed) return;
    }

    // Collect baseline changes needing reason
    final changes = _collectBaselineChanges();
    if (changes.isNotEmpty) {
      final confirmed = await _showChangeReasonDialog(changes);
      if (!confirmed) return;
    }

    // Ask for submitter name
    final name = await _showSubmitterDialog();
    if (name == null) return;

    setState(() {
      _submitting = true;
      _submitError = null;
      _submitSuccess = null;
    });

    try {
      final rows = <Map<String, dynamic>>[];
      for (final act in _data!.activities) {
        for (final floor in _data!.floors) {
          final key = _cellKey(act.id, floor.id);
          final ctrl = _ctrl[key];
          if (ctrl == null) continue;
          final totalEst = _parse(ctrl[0].text);
          final estActual = _parse(ctrl[1].text);
          final actual = _parse(ctrl[2].text);
          if (totalEst == null && estActual == null && actual == null) continue;
          rows.add({
            'activity_id': act.id,
            'floor_id': floor.id,
            'total_estimated_qty': totalEst,
            'estimate_actual_qty_till_date': estActual,
            'actual_qty': actual,
            'justification': _justifications[key],
            'baseline_change_reason': _changeReasons[key],
          });
        }
      }

      await QsApi.submitEntries(
        projectId: _projectId!,
        month: _month,
        submittedBy: name,
        rows: rows,
      );

      setState(() {
        _submitting = false;
        _submitSuccess = 'Submitted ${rows.length} entries for $_month successfully.';
      });
      await _loadData();
    } catch (e) {
      setState(() {
        _submitting = false;
        _submitError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool> _showJustificationDialog(List<(String, int, int)> overruns) async {
    final controllers = {for (final o in overruns) '${o.$2}:${o.$3}': TextEditingController()};
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Justification Required'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Actual Qty exceeds Total Estimated Qty for ${overruns.length} cell(s). '
                  'Please provide justification for each.',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ...overruns.map((o) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: controllers['${o.$2}:${o.$3}'],
                            maxLines: 2,
                            decoration: const InputDecoration(
                              hintText: 'Enter justification…',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.all(8),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBrand),
            onPressed: () {
              for (final o in overruns) {
                final key = '${o.$2}:${o.$3}';
                _justifications[key] = controllers[key]!.text.trim();
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    for (final c in controllers.values) { c.dispose(); }
    return result ?? false;
  }

  Future<bool> _showChangeReasonDialog(List<(String, int, int)> changes) async {
    final controllers = {for (final c in changes) '${c.$2}:${c.$3}': TextEditingController()};
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason for Baseline Change'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Estimated Qty (GFC Drawing) has been changed for ${changes.length} cell(s). '
                  'A reason is required for audit trail.',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ...changes.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: controllers['${c.$2}:${c.$3}'],
                            maxLines: 2,
                            decoration: const InputDecoration(
                              hintText: 'Reason for change…',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.all(8),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBrand),
            onPressed: () {
              for (final c in changes) {
                final key = '${c.$2}:${c.$3}';
                _changeReasons[key] = controllers[key]!.text.trim();
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    for (final c in controllers.values) { c.dispose(); }
    return result ?? false;
  }

  Future<String?> _showSubmitterDialog() async {
    final ctrl = TextEditingController(text: _submittedBy ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your Name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter your name for the audit record',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBrand),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) _submittedBy = result;
    return (result?.isEmpty ?? true) ? null : result;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        QsSelector(
          projects: _projects,
          selectedProjectId: _projectId,
          selectedMonth: _month,
          onProjectChanged: (id) {
            setState(() => _projectId = id);
            _loadData();
          },
          onMonthChanged: (m) {
            setState(() => _month = m);
            if (_projectId != null) _loadData();
          },
          trailing: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _data != null ? _pasteFromClipboard : null,
                icon: const Icon(Icons.content_paste, size: 15),
                label: const Text('Paste from Excel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kBrand,
                  side: const BorderSide(color: kBrand),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _data != null ? _copyToClipboard : null,
                icon: const Icon(Icons.content_copy, size: 15),
                label: const Text('Copy to Excel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              PrimaryButton(
                label: 'Submit',
                icon: Icons.send_outlined,
                onPressed: _data != null ? _submit : null,
                loading: _submitting,
              ),
            ],
          ),
        ),
        if (_submitSuccess != null) _banner(_submitSuccess!, kSuccess),
        if (_submitError != null)
          _banner(_submitError!, kError, isError: true),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _banner(String msg, Color color, {bool isError = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_projectId == null) {
      return const EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'Select a project',
        subtitle: 'Choose a project and month above to start entering data',
      );
    }
    if (_loading) return const LoadingCenter(message: 'Loading quantity data…');
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _loadData);
    if (_data == null) return const SizedBox();
    if (_data!.floors.isEmpty) {
      return const EmptyState(
        icon: Icons.layers_outlined,
        title: 'No floors configured',
        subtitle: 'Add floors to this project in the Setup tab',
      );
    }
    if (_data!.activities.isEmpty) {
      return const EmptyState(
        icon: Icons.construction_outlined,
        title: 'No activities configured',
        subtitle: 'Add activities in the Setup tab',
      );
    }
    return _buildGrid();
  }

  Widget _buildGrid() {
    final data = _data!;
    final floors = data.floors;
    final acts = data.activities;
    final totalCols = _kRowHeaderW + _kUnitW + floors.length * 3 * _kCellW;

    return Scrollbar(
      controller: _hScrollCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _hScrollCtrl,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalCols,
          child: Column(
            children: [
              _buildColumnHeaders(floors),
              _buildSubHeaders(floors),
              Expanded(
                child: ListView.builder(
                  itemCount: acts.length,
                  itemBuilder: (_, i) => _buildDataRow(acts[i], floors, i),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColumnHeaders(List<QsFloor> floors) {
    return Container(
      height: _kHeaderH,
      decoration: const BoxDecoration(
        color: Color(0xFF0066CC),
      ),
      child: Row(
        children: [
          _colHeader('Activity', _kRowHeaderW, textColor: Colors.white),
          _colHeader('Unit', _kUnitW, textColor: Colors.white),
          ...floors.map((f) => _colHeader(
                f.name,
                _kCellW * 3,
                textColor: Colors.white,
              )),
        ],
      ),
    );
  }

  Widget _buildSubHeaders(List<QsFloor> floors) {
    return Container(
      height: _kSubHeaderH,
      color: const Color(0xFFD6E4F7),
      child: Row(
        children: [
          SizedBox(width: _kRowHeaderW),
          SizedBox(width: _kUnitW),
          ...floors.expand((_) => [
                _subHeader('Total Est.\n(Drawing)', _kCellW),
                _subHeader('Est. Actual\nTill Date', _kCellW),
                _subHeader('Actual Qty', _kCellW),
              ]),
        ],
      ),
    );
  }

  Widget _colHeader(String text, double width, {Color textColor = Colors.white}) {
    return SizedBox(
      width: width,
      child: Center(
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textColor)),
      ),
    );
  }

  Widget _subHeader(String text, double width) {
    return SizedBox(
      width: width,
      child: Center(
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildDataRow(QsActivity act, List<QsFloor> floors, int rowIdx) {
    final bg = rowIdx.isEven ? Colors.white : const Color(0xFFF8FAFC);
    return Container(
      height: _kRowH,
      color: bg,
      child: Row(
        children: [
          _rowLabel(act.name, _kRowHeaderW),
          _rowLabel(act.unit, _kUnitW, grey: true),
          ...floors.expand((floor) => _buildCellGroup(act, floor)),
        ],
      ),
    );
  }

  List<Widget> _buildCellGroup(QsActivity act, QsFloor floor) {
    final key = _cellKey(act.id, floor.id);
    final ctrl = _ctrl[key]!;
    final focus = _focus[key]!;
    final cell = _data!.cell(act.id, floor.id);
    final isOverrun = _hasOverrun(act.id, floor.id);

    return [
      // Total Estimated Qty — can be locked (baseline exists)
      _CellField(
        controller: ctrl[0],
        focusNode: focus[0],
        width: _kCellW,
        height: _kRowH,
        isOverrun: false,
        isLocked: cell?.baselineLocked ?? false,
        lockedTooltip: 'GFC Drawing qty — locked. Changing will require a reason.',
      ),
      // Estimate of Actual Qty Till Date
      _CellField(
        controller: ctrl[1],
        focusNode: focus[1],
        width: _kCellW,
        height: _kRowH,
        isOverrun: isOverrun,
      ),
      // Actual Qty
      _CellField(
        controller: ctrl[2],
        focusNode: focus[2],
        width: _kCellW,
        height: _kRowH,
        isOverrun: isOverrun,
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  Widget _rowLabel(String text, double width, {bool grey = false}) {
    return Container(
      width: width,
      height: _kRowH,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: grey ? Colors.grey.shade500 : Colors.black87,
        ),
      ),
    );
  }
}

// ─── Individual editable cell ─────────────────────────────────────────────────

class _CellField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final double width;
  final double height;
  final bool isOverrun;
  final bool isLocked;
  final String? lockedTooltip;
  final ValueChanged<String>? onChanged;

  const _CellField({
    required this.controller,
    required this.focusNode,
    required this.width,
    required this.height,
    required this.isOverrun,
    this.isLocked = false,
    this.lockedTooltip,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = isOverrun
        ? const Color(0xFFFFC7CE).withValues(alpha: 0.5)
        : isLocked
            ? const Color(0xFFF0F4FF)
            : Colors.transparent;

    Widget field = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200),
          bottom: BorderSide(color: Colors.grey.shade100),
          left: isOverrun ? const BorderSide(color: Color(0xFFD32F2F), width: 1.5) : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        onChanged: onChanged,
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          hintText: '—',
          hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 12),
          suffixIcon: isLocked
              ? const Icon(Icons.lock_outline, size: 12, color: Color(0xFF0066CC))
              : null,
          suffixIconConstraints: const BoxConstraints(maxWidth: 18, maxHeight: 18),
        ),
        style: TextStyle(
          fontSize: 12,
          color: isOverrun ? const Color(0xFF9C0006) : Colors.black87,
          fontWeight: isOverrun ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );

    if (isLocked && lockedTooltip != null) {
      field = Tooltip(message: lockedTooltip!, child: field);
    }
    return field;
  }
}
