import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/download_service.dart' show downloadFileOnWeb;
import '../../services/project_api.dart';
import '../../services/schedule_api.dart';

part 'schedule_grid.dart';
part 'gantt_painters.dart';

const Color _kBrand = Color(0xFF0066CC);
const Color _kGroup = Color(0xFF1A1A2E);
const Color _kError = Color(0xFFD32F2F);
const double _kRowH = 44.0;
const double _kGanttHeaderH = 40.0;
const double _kPxPerDay = 22.0;
const double _kSplitterW = 6.0;

class ProjectScheduleScreen extends StatefulWidget {
  const ProjectScheduleScreen({super.key});

  @override
  State<ProjectScheduleScreen> createState() => _ProjectScheduleScreenState();
}

class _ProjectScheduleScreenState extends State<ProjectScheduleScreen> {
  List<Project> _projects = [];
  Project? _selectedProject;
  List<PmActivity> _activities = [];
  List<ProjectFloor> _floors = [];
  bool _loading = false;
  String? _error;
  String? _gridError;
  bool _showMobileChart = false;

  double _tableWidth = 620;
  final Set<int> _collapsed = {};
  int? _editingId;
  int? _addToGroupId; // group whose inline "add activity" row is open
  bool _exporting = false;
  final _newRowKey = GlobalKey<_EditableRowState>();

  // Sync scroll controllers
  final _tableVertCtrl = ScrollController();
  // Explicit controller: a Scrollbar without one falls back to the
  // PrimaryScrollController, which isn't attached here and asserts mid-drag.
  final _tableHorzCtrl = ScrollController();
  final _tableListKey = GlobalKey();

  // Row drag state
  int? _dragId;
  _DropHint? _dropHint;
  final _ganttVertCtrl = ScrollController();
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _tableVertCtrl.addListener(_onTableScroll);
    _ganttVertCtrl.addListener(_onGanttScroll);
    _loadProjects();
  }

  @override
  void dispose() {
    _tableVertCtrl.removeListener(_onTableScroll);
    _ganttVertCtrl.removeListener(_onGanttScroll);
    _tableVertCtrl.dispose();
    _tableHorzCtrl.dispose();
    _ganttVertCtrl.dispose();
    super.dispose();
  }

  void _onTableScroll() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (_ganttVertCtrl.hasClients) {
      final offset = _tableVertCtrl.offset.clamp(
        0.0,
        _ganttVertCtrl.position.maxScrollExtent,
      );
      _ganttVertCtrl.jumpTo(offset);
    }
    _isSyncing = false;
  }

  void _onGanttScroll() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (_tableVertCtrl.hasClients) {
      final offset = _ganttVertCtrl.offset.clamp(
        0.0,
        _tableVertCtrl.position.maxScrollExtent,
      );
      _tableVertCtrl.jumpTo(offset);
    }
    _isSyncing = false;
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await ProjectApi.listProjects();
      if (mounted) setState(() => _projects = projects);
    } catch (_) {}
  }

  Future<void> _loadSchedule() async {
    if (_selectedProject == null) return;
    final projectId = _selectedProject!.id;
    setState(() {
      _loading = _activities.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ScheduleApi.getSchedule(projectId),
        ProjectApi.listFloors(projectId),
      ]);
      if (mounted) {
        setState(() {
          _activities = results[0] as List<PmActivity>;
          _floors = results[1] as List<ProjectFloor>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Tree ──────────────────────────────────────────────────────────────────

  Map<int, PmActivity> get _byId => {for (final a in _activities) a.id: a};

  Map<int?, List<PmActivity>> _childrenByParent() {
    final ids = _byId;
    final out = <int?, List<PmActivity>>{};
    for (final a in _activities) {
      // Orphans (parent missing) show at top level rather than vanishing.
      final key = ids.containsKey(a.parentId) ? a.parentId : null;
      out.putIfAbsent(key, () => []).add(a);
    }
    return out;
  }

  /// Depth-first tree order; children of collapsed groups are skipped.
  List<_Row> _visibleRows() {
    final children = _childrenByParent();
    final rows = <_Row>[];
    final seen = <int>{};
    final datedMemo = <int, bool>{};
    bool dated(PmActivity a, [int guard = 0]) {
      if (!a.isGroup) return true;
      if (guard > _activities.length) return false;
      return datedMemo[a.id] ??= (children[a.id] ?? const <PmActivity>[]).any(
        (k) => dated(k, guard + 1),
      );
    }

    void walk(int? parent, int depth) {
      for (final a in children[parent] ?? const <PmActivity>[]) {
        if (!seen.add(a.id)) continue;
        final kids = children[a.id] ?? const [];
        rows.add(_Row(a, depth, kids.isNotEmpty, dated(a)));
        if (!_collapsed.contains(a.id)) walk(a.id, depth + 1);
      }
    }

    walk(null, 0);
    return rows;
  }

  int _depthOf(int? groupId) {
    var depth = 0;
    final ids = _byId;
    var node = groupId == null ? null : ids[groupId];
    while (node != null && depth <= ids.length) {
      depth++;
      node = node.parentId == null ? null : ids[node.parentId];
    }
    return depth;
  }

  /// The group a new row lands in: the last row itself if it's a group,
  /// otherwise the group the last row belongs to.
  PmActivity? _contextGroup(List<_Row> rows) {
    if (rows.isEmpty) return null;
    final last = rows.last.activity;
    if (last.isGroup) return last;
    return last.parentId == null ? null : _byId[last.parentId];
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildHeader() {
    // Narrow panes: icon-only buttons so the header never overflows.
    final compact = MediaQuery.sizeOf(context).width < 1180;
    final exportIcon = _exporting
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.download_outlined, size: 18);
    final canExport = !_exporting && _activities.isNotEmpty;
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
            child: const Icon(Icons.timeline, color: _kBrand, size: 22),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project Schedule',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              Text(
                'Plan and track activities with Gantt view',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Flexible(
            child: _ProjectDropdown(
              projects: _projects,
              selected: _selectedProject,
              onChanged: (p) {
                setState(() {
                  _selectedProject = p;
                  _activities = [];
                  _floors = [];
                  _collapsed.clear();
                  _editingId = null;
                  _addToGroupId = null;
                  _error = null;
                  _gridError = null;
                });
                _loadSchedule();
              },
            ),
          ),
          const Spacer(),
          if (_selectedProject != null && compact) ...[
            IconButton.outlined(
              tooltip: 'Export schedule + Gantt to Excel',
              color: _kBrand,
              onPressed: canExport ? _export : null,
              icon: exportIcon,
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Add activity',
              style: IconButton.styleFrom(backgroundColor: _kBrand),
              onPressed: _focusNewRow,
              icon: const Icon(Icons.add, size: 18),
            ),
          ] else if (_selectedProject != null) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _kBrand,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: canExport ? _export : null,
              icon: exportIcon,
              label: const Text('Export Excel', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBrand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _focusNewRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Activity', style: TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  void _focusNewRow() {
    setState(() {
      _editingId = null;
      _addToGroupId = null;
      _showMobileChart = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tableVertCtrl.hasClients) {
        _tableVertCtrl.jumpTo(_tableVertCtrl.position.maxScrollExtent);
      }
      _newRowKey.currentState?.focusName();
    });
  }

  Widget _buildBody() {
    if (_selectedProject == null) {
      return _EmptyState(
        icon: Icons.timeline_outlined,
        title: 'No project selected',
        subtitle: _projects.isEmpty
            ? 'No projects yet. Ask an administrator to create a project.'
            : 'Select a project above to view its schedule.',
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kBrand));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _kError)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadSchedule,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final rows = _visibleRows();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isMobile = constraints.maxWidth < 720;
        if (isMobile) return _buildMobileView(rows);
        return _buildDesktopView(rows, constraints.maxWidth);
      },
    );
  }

  Widget _buildMobileView(List<_Row> rows) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Table'),
                icon: Icon(Icons.table_rows_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Gantt'),
                icon: Icon(Icons.bar_chart_outlined),
              ),
            ],
            selected: {_showMobileChart},
            onSelectionChanged: (s) =>
                setState(() => _showMobileChart = s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _kBrand.withValues(alpha: 0.1);
                }
                return null;
              }),
            ),
          ),
        ),
        Expanded(
          child: _showMobileChart
              ? _buildGanttPanel(rows)
              : _buildTablePanel(rows),
        ),
      ],
    );
  }

  Widget _buildDesktopView(List<_Row> rows, double maxWidth) {
    final maxTable = math.max(320.0, maxWidth - 240);
    final tableW = _tableWidth.clamp(320.0, maxTable);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: tableW, child: _buildTablePanel(rows)),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(
              () => _tableWidth = (tableW + d.delta.dx).clamp(320.0, maxTable),
            ),
            onDoubleTap: () => setState(() => _tableWidth = _kGridWidth),
            child: Tooltip(
              message: 'Drag to resize · double-click to fit all columns',
              waitDuration: const Duration(milliseconds: 800),
              child: Container(
                width: _kSplitterW,
                color: Colors.grey.shade200,
                child: Center(
                  child: Container(
                    width: 2,
                    height: 32,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: _buildGanttPanel(rows)),
      ],
    );
  }

  /// Table lines in display order; null marks the inline "add in group" row,
  /// placed right after the group's last visible descendant.
  List<_Row?> _slots(List<_Row> rows) {
    final slots = <_Row?>[...rows];
    final g = rows.indexWhere((r) => r.activity.id == _addToGroupId);
    if (g < 0) return slots;
    var end = g + 1;
    while (end < rows.length && rows[end].depth > rows[g].depth) {
      end++;
    }
    slots.insert(end, null);
    return slots;
  }

  Widget _buildTablePanel(List<_Row> rows) {
    final predLabel = {for (final a in _activities) a.id: _activityLabel(a)};
    final context_ = _contextGroup(rows);
    final newDepth = _depthOf(context_?.id);
    final slots = _slots(rows);
    final addGroup = _addToGroupId == null ? null : _byId[_addToGroupId];

    return Column(
      children: [
        Expanded(
          child: Scrollbar(
            controller: _tableHorzCtrl,
            thumbVisibility: true,
            notificationPredicate: (n) => n.depth == 0,
            child: SingleChildScrollView(
              controller: _tableHorzCtrl,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _kGridWidth,
                child: Column(
                  children: [
                    const _TableHeader(),
                    Expanded(
                      child: ListView.builder(
                        key: _tableListKey,
                        controller: _tableVertCtrl,
                        itemCount: slots.length + 1,
                        itemExtent: _kRowH,
                        itemBuilder: (ctx, i) {
                          if (i == slots.length) {
                            return _EditableRow(
                              key: _newRowKey,
                              depth: newDepth,
                              activities: _activities,
                              floors: _floors,
                              onSubmit: (d) => _create(d, context_),
                            );
                          }
                          final r = slots[i];
                          if (r == null) {
                            return _EditableRow(
                              key: ValueKey('add-in-${addGroup!.id}'),
                              depth: _depthOf(addGroup.id),
                              groupName: addGroup.name,
                              activities: _activities,
                              floors: _floors,
                              onSubmit: (d) => _createIn(d, addGroup),
                              onCancel: () =>
                                  setState(() => _addToGroupId = null),
                            );
                          }
                          final a = r.activity;
                          if (_editingId == a.id) {
                            return _EditableRow(
                              key: ValueKey('edit-${a.id}'),
                              existing: a,
                              depth: r.depth,
                              activities: _activities,
                              floors: _floors,
                              onSubmit: (d) => _update(a, d),
                              onCancel: () => setState(() => _editingId = null),
                            );
                          }
                          return _ActivityRow(
                            key: ValueKey('row-${a.id}'),
                            row: r,
                            dragHandle: _dragHandle(a),
                            isDragSource: _dragId == a.id,
                            indicator: _dropHint?.targetId == a.id
                                ? _dropHint!.indicator
                                : _DropIndicator.none,
                            indicatorDepth: _dropHint?.targetId == a.id
                                ? _dropHint!.depth
                                : 0,
                            predecessorLabel: predLabel[a.predecessorId],
                            collapsed: _collapsed.contains(a.id),
                            onToggleCollapse: () => setState(() {
                              if (!_collapsed.remove(a.id)) {
                                _collapsed.add(a.id);
                              }
                            }),
                            onEdit: () => setState(() {
                              _editingId = a.id;
                              _addToGroupId = null;
                            }),
                            onDelete: () => _deleteActivity(a),
                            onIndent: _indentTarget(a) == null
                                ? null
                                : () => _indent(a),
                            onOutdent: a.parentId == null
                                ? null
                                : () => _outdent(a),
                            onAddChild: a.isGroup
                                ? () => setState(() {
                                    _collapsed.remove(a.id);
                                    _editingId = null;
                                    _addToGroupId = a.id;
                                  })
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_gridError != null)
          _ErrorBar(
            message: _gridError!,
            onClose: () => setState(() => _gridError = null),
          ),
      ],
    );
  }

  Widget _buildGanttPanel(List<_Row> rows) {
    final dates = _ganttDateRange(rows);
    if (dates == null) {
      return const Center(
        child: Text(
          'Add activities to see the Gantt chart',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }
    final (minDate, maxDate) = dates;
    final totalDays = maxDate.difference(minDate).inDays + 14;
    final ganttW = totalDays * _kPxPerDay;
    final slots = _slots(rows);
    // +1 slot matches the table's inline new-entry row so scrolling stays aligned.
    final ganttH = (slots.length + 1) * _kRowH;

    // One horizontal scroller for header + body keeps month labels over their bars.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: ganttW,
        child: Column(
          children: [
            SizedBox(
              height: _kGanttHeaderH,
              width: ganttW,
              child: CustomPaint(
                painter: _GanttHeaderPainter(
                  minDate: minDate,
                  totalDays: totalDays,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _ganttVertCtrl,
                child: _GanttBody(
                  rows: slots,
                  minDate: minDate,
                  totalDays: totalDays,
                  width: ganttW,
                  height: ganttH,
                  details: _barDetails,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<(String, String)> _barDetails(_Row row) {
    final a = row.activity;
    final lines = <(String, String)>[];
    if (a.isGroup) {
      final all = <PmActivity>[];
      final children = _childrenByParent();
      void collect(int id) {
        for (final k in children[id] ?? const <PmActivity>[]) {
          all.add(k);
          if (k.isGroup && all.length <= _activities.length) collect(k.id);
        }
      }

      collect(a.id);
      final acts = all.where((k) => !k.isGroup).length;
      final subs = all.length - acts;
      lines.add((
        'Contains',
        '$acts ${acts == 1 ? 'activity' : 'activities'}'
            '${subs > 0 ? ' · $subs sub-group${subs == 1 ? '' : 's'}' : ''}',
      ));
    } else {
      lines.add(('Floor', a.floorName ?? '—'));
    }
    lines
      ..add(('Start', _fmtDate(a.startDate)))
      ..add(('Finish', _fmtDate(a.finishDate)))
      ..add((
        'Duration',
        '${a.durationDays} ${a.durationDays == 1 ? 'day' : 'days'}',
      ));
    if (a.predecessorId != null) {
      final p = _byId[a.predecessorId];
      lines.add((
        'Predecessor',
        '${p == null ? '?' : _activityLabel(p)}'
            '${a.lagDays != 0 ? ' (+${a.lagDays}d lag)' : ''}',
      ));
    }
    if (a.quantity != null) {
      lines.add((
        'Quantity',
        '${a.quantity}${a.unit != null ? ' ${a.unit}' : ''}',
      ));
    }
    final parent = a.parentId == null ? null : _byId[a.parentId];
    if (parent != null) lines.add(('Group', parent.name));
    return lines;
  }

  (DateTime, DateTime)? _ganttDateRange(List<_Row> rows) {
    DateTime? min, max;
    for (final r in rows) {
      if (!r.hasDates) continue;
      final s = DateTime.tryParse(r.activity.startDate);
      final f = DateTime.tryParse(r.activity.finishDate);
      if (s != null && (min == null || s.isBefore(min))) min = s;
      if (f != null && (max == null || f.isAfter(max))) max = f;
    }
    if (min == null || max == null) return null;
    return (min.subtract(const Duration(days: 3)), max);
  }

  // ─── Mutations ─────────────────────────────────────────────────────────────

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<bool> _create(_Draft d, PmActivity? contextGroup) async {
    int? parentId = contextGroup?.id;
    if (d.isGroup && contextGroup != null) {
      final choice = await _askGroupPlacement(d.name, contextGroup);
      if (choice == null) return false;
      parentId = choice ? contextGroup.id : contextGroup.parentId;
    }
    try {
      await ScheduleApi.createActivity(
        projectId: _selectedProject!.id,
        rowType: d.rowType,
        name: d.name,
        parentId: parentId,
        floorId: d.floorId,
        durationDays: d.days,
        startDate: d.start == null ? null : _isoOf(d.start!),
        predecessorId: d.predId,
        lagDays: d.lag,
        quantity: d.qty,
        unit: d.unit,
      );
      setState(() => _gridError = null);
      await _loadSchedule();
      return true;
    } catch (e) {
      if (mounted) setState(() => _gridError = _msg(e));
      return false;
    }
  }

  /// Entry row opened from a group: the row always lands inside that group.
  Future<bool> _createIn(_Draft d, PmActivity group) async {
    try {
      await ScheduleApi.createActivity(
        projectId: _selectedProject!.id,
        rowType: d.rowType,
        name: d.name,
        parentId: group.id,
        floorId: d.floorId,
        durationDays: d.days,
        startDate: d.start == null ? null : _isoOf(d.start!),
        predecessorId: d.predId,
        lagDays: d.lag,
        quantity: d.qty,
        unit: d.unit,
      );
      setState(() => _gridError = null);
      await _loadSchedule();
      return true;
    } catch (e) {
      if (mounted) setState(() => _gridError = _msg(e));
      return false;
    }
  }

  // ─── Drag to reorder (within a group only) ───────────────────────────────────

  Widget _dragHandle(PmActivity a) {
    return Draggable<PmActivity>(
      data: a,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(activity: a),
      onDragStarted: () => setState(() {
        _dragId = a.id;
        _dropHint = null;
      }),
      onDragUpdate: (d) => _onDragUpdate(a, d.globalPosition),
      onDragEnd: (_) => _onDragEnd(a),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: 'Drag to reorder within its group',
          waitDuration: const Duration(milliseconds: 600),
          child: SizedBox(
            width: 20,
            height: _kRowH,
            child: Icon(Icons.drag_indicator, size: 15, color: Colors.grey.shade500),
          ),
        ),
      ),
    );
  }

  void _onDragUpdate(PmActivity dragged, Offset global) {
    final box = _tableListKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);

    // Auto-scroll when the pointer nears the top/bottom edge of the list.
    if (_tableVertCtrl.hasClients) {
      final pos = _tableVertCtrl.position;
      const edge = 36.0, step = 14.0;
      if (local.dy < edge && pos.pixels > 0) {
        _tableVertCtrl.jumpTo(math.max(0, pos.pixels - step));
      } else if (local.dy > box.size.height - edge && pos.pixels < pos.maxScrollExtent) {
        _tableVertCtrl.jumpTo(math.min(pos.maxScrollExtent, pos.pixels + step));
      }
    }

    _DropHint? hint;
    if (local.dy >= 0 && local.dy <= box.size.height) {
      final y = local.dy + (_tableVertCtrl.hasClients ? _tableVertCtrl.offset : 0);
      final slots = _slots(_visibleRows());
      final i = y ~/ _kRowH;
      if (i >= 0 && i < slots.length && slots[i] != null) {
        hint = _hintFor(dragged, slots[i]!, (y % _kRowH) < _kRowH / 2);
      }
    }
    if (hint?.targetId != _dropHint?.targetId ||
        hint?.indicator != _dropHint?.indicator) {
      setState(() => _dropHint = hint);
    }
  }

  bool _isDescendantOf(PmActivity a, int ancestorId) {
    final ids = _byId;
    var node = a.parentId == null ? null : ids[a.parentId];
    var guard = 0;
    while (node != null && guard++ <= ids.length) {
      if (node.id == ancestorId) return true;
      node = node.parentId == null ? null : ids[node.parentId];
    }
    return false;
  }

  /// Decides what dropping [dragged] onto [target] would do. Only positions
  /// among the dragged row's siblings are allowed; anything else is invalid.
  _DropHint? _hintFor(PmActivity dragged, _Row target, bool upperHalf) {
    final t = target.activity;
    if (t.id == dragged.id || _isDescendantOf(t, dragged.id)) return null; // itself: no-op

    final ids = _byId;
    int? norm(int? id) => ids.containsKey(id) ? id : null;
    final parentId = norm(dragged.parentId);
    final siblings = (_childrenByParent()[parentId] ?? const <PmActivity>[])
        .where((x) => x.id != dragged.id)
        .toList();
    final parentDepth = parentId == null ? -1 : _depthOf(parentId) - 1;
    final sibDepth = parentDepth + 1;

    // Sibling row: before/after it. An expanded sibling group only takes
    // "before", since "after" its header would read as "inside" the group.
    if (norm(t.parentId) == parentId) {
      final idx = siblings.indexWhere((x) => x.id == t.id);
      final expandedGroup = t.isGroup && target.hasChildren && !_collapsed.contains(t.id);
      final before = upperHalf || expandedGroup;
      return _DropHint(
        targetId: t.id,
        indicator: before ? _DropIndicator.before : _DropIndicator.after,
        depth: sibDepth,
        siblingIndex: before ? idx : idx + 1,
      );
    }

    // The group's own header: move to the top of the group.
    if (t.id == parentId) {
      return _DropHint(
        targetId: t.id,
        indicator: _DropIndicator.after,
        depth: sibDepth,
        siblingIndex: 0,
      );
    }

    // Lower half of the last visible row inside a sibling group:
    // "after that group" (the only way to drop below a trailing group).
    if (!upperHalf) {
      final rows = _visibleRows();
      final ti = rows.indexWhere((r) => r.activity.id == t.id);
      for (var j = ti - 1; j >= 0; j--) {
        final r = rows[j];
        if (r.depth < target.depth && norm(r.activity.parentId) == parentId) {
          final nextIsOutside = ti + 1 >= rows.length || rows[ti + 1].depth <= r.depth;
          if (r.activity.isGroup && nextIsOutside) {
            final idx = siblings.indexWhere((x) => x.id == r.activity.id);
            return _DropHint(
              targetId: t.id,
              indicator: _DropIndicator.after,
              depth: sibDepth,
              siblingIndex: idx + 1,
            );
          }
          break;
        }
      }
    }

    // Anything else is a different group.
    final targetGroup = t.isGroup ? t : ids[t.parentId];
    return _DropHint(
      targetId: t.id,
      indicator: _DropIndicator.invalid,
      depth: 0,
      invalidGroupName: targetGroup?.name ?? 'the top level',
    );
  }

  Future<void> _onDragEnd(PmActivity dragged) async {
    final hint = _dropHint;
    setState(() {
      _dragId = null;
      _dropHint = null;
    });
    if (hint == null) return;

    if (hint.indicator == _DropIndicator.invalid) {
      final ids = _byId;
      final own = dragged.parentId == null ? null : ids[dragged.parentId];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.block, color: _kError),
          title: const Text("Can't move there"),
          content: Text(
            '"${dragged.name}" belongs to ${own == null ? 'the top level' : '"${own.name}"'}. '
            'Rows can only be rearranged within their own group, so it can\'t be dropped '
            'into ${hint.invalidGroupName == 'the top level' ? 'the top level' : '"${hint.invalidGroupName}"'}.\n\n'
            'To move it to another group, use the indent / outdent buttons.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kBrand, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final ids = _byId;
    final parentId = ids.containsKey(dragged.parentId) ? dragged.parentId : null;
    final current = (_childrenByParent()[parentId] ?? const <PmActivity>[]).map((x) => x.id).toList();
    final order = current.where((id) => id != dragged.id).toList()
      ..insert(hint.siblingIndex!.clamp(0, current.length - 1), dragged.id);
    if (order.join(',') == current.join(',')) return;
    await _applySiblingOrder(order);
  }

  /// Optimistically reorders siblings (reusing their slots in the flat list so
  /// the tree updates immediately), then saves.
  Future<void> _applySiblingOrder(List<int> ids) async {
    final slotsIdx = <int>[
      for (var k = 0; k < _activities.length; k++)
        if (ids.contains(_activities[k].id)) k,
    ];
    final byId = _byId;
    final next = [..._activities];
    for (var k = 0; k < slotsIdx.length; k++) {
      next[slotsIdx[k]] = byId[ids[k]]!;
    }
    setState(() {
      _activities = next;
      _gridError = null;
    });
    try {
      await ScheduleApi.reorderSiblings(_selectedProject!.id, ids);
    } catch (e) {
      if (mounted) setState(() => _gridError = _msg(e));
      await _loadSchedule();
    }
  }

  Future<void> _export() async {
    final project = _selectedProject;
    if (project == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ScheduleApi.exportExcel(project.id);
      final safe = project.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      downloadFileOnWeb(bytes, 'schedule_$safe.xlsx');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${_msg(e)}'),
            backgroundColor: _kError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// true → inside [group], false → new group at the same level, null → cancel.
  Future<bool?> _askGroupPlacement(String name, PmActivity group) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
        title: const Text('Where does this group go?'),
        content: Text(
          'Does "$name" fall under "${group.name}", or is it a new group?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('New group'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBrand,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Inside "${group.name}"'),
          ),
        ],
      ),
    );
  }

  Future<bool> _update(PmActivity a, _Draft d) async {
    try {
      if (a.isGroup) {
        await ScheduleApi.updateActivity(a.id, name: d.name);
      } else {
        await ScheduleApi.updateActivity(
          a.id,
          name: d.name,
            floorId: d.floorId,
          durationDays: d.days,
          startDate: _isoOf(d.start!),
          predecessorId: d.predId,
          clearPredecessor: d.predId == null && a.predecessorId != null,
          lagDays: d.lag,
          quantity: d.qty,
          clearQuantity: d.qty == null && a.quantity != null,
          unit: d.unit ?? '',
        );
      }
      setState(() {
        _editingId = null;
        _gridError = null;
      });
      await _loadSchedule();
      return true;
    } catch (e) {
      if (mounted) setState(() => _gridError = _msg(e));
      return false;
    }
  }

  /// Nearest earlier sibling that is a group — indenting moves the row into it.
  PmActivity? _indentTarget(PmActivity a) {
    final siblings =
        _childrenByParent()[_byId.containsKey(a.parentId)
            ? a.parentId
            : null] ??
        [];
    final idx = siblings.indexWhere((s) => s.id == a.id);
    for (var i = idx - 1; i >= 0; i--) {
      if (siblings[i].isGroup) return siblings[i];
    }
    return null;
  }

  Future<void> _indent(PmActivity a) async {
    final target = _indentTarget(a);
    if (target == null) return;
    await _move(a, target.id);
  }

  Future<void> _outdent(PmActivity a) async {
    final parent = _byId[a.parentId];
    await _move(a, parent?.parentId);
  }

  Future<void> _move(PmActivity a, int? parentId) async {
    try {
      await ScheduleApi.updateActivity(
        a.id,
        parentId: parentId,
        clearParent: parentId == null,
      );
      if (parentId != null) _collapsed.remove(parentId);
      setState(() => _gridError = null);
      await _loadSchedule();
    } catch (e) {
      if (mounted) setState(() => _gridError = _msg(e));
    }
  }

  Future<void> _deleteActivity(PmActivity a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.isGroup ? 'Delete group?' : 'Delete activity?'),
        content: Text(
          a.isGroup
              ? 'Delete group "${a.name}"? It must be empty first.'
              : 'Delete "${a.name}"? Other activities depending on it must be unlinked first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ScheduleApi.deleteActivity(a.id);
      _loadSchedule();
    } catch (e) {
      if (mounted) setState(() => _gridError = _msg(e));
    }
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _ProjectDropdown extends StatelessWidget {
  final List<Project> projects;
  final Project? selected;
  final ValueChanged<Project?> onChanged;

  const _ProjectDropdown({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

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
            .map(
              (p) => DropdownMenuItem<int?>(
                value: p.id,
                child: Text(
                  p.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            )
            .toList(),
        onChanged: (id) {
          if (id == null) return;
          final p = projects.firstWhere((p) => p.id == id);
          onChanged(p);
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}
