import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _newRowKey = GlobalKey<_EditableRowState>();

  // Sync scroll controllers
  final _tableVertCtrl = ScrollController();
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
      return datedMemo[a.id] ??=
          (children[a.id] ?? const <PmActivity>[]).any((k) => dated(k, guard + 1));
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
              Text('Project Schedule',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
              Text('Plan and track activities with Gantt view',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(width: 24),
          _ProjectDropdown(
            projects: _projects,
            selected: _selectedProject,
            onChanged: (p) {
              setState(() {
                _selectedProject = p;
                _activities = [];
                _floors = [];
                _collapsed.clear();
                _editingId = null;
                _error = null;
                _gridError = null;
              });
              _loadSchedule();
            },
          ),
          const Spacer(),
          if (_selectedProject != null)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBrand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _focusNewRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Activity', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }

  void _focusNewRow() {
    setState(() {
      _editingId = null;
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
    if (_loading) return const Center(child: CircularProgressIndicator(color: _kBrand));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _kError)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadSchedule, child: const Text('Retry')),
          ],
        ),
      );
    }

    final rows = _visibleRows();
    return LayoutBuilder(builder: (ctx, constraints) {
      final isMobile = constraints.maxWidth < 720;
      if (isMobile) return _buildMobileView(rows);
      return _buildDesktopView(rows, constraints.maxWidth);
    });
  }

  Widget _buildMobileView(List<_Row> rows) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Table'), icon: Icon(Icons.table_rows_outlined)),
              ButtonSegment(value: true, label: Text('Gantt'), icon: Icon(Icons.bar_chart_outlined)),
            ],
            selected: {_showMobileChart},
            onSelectionChanged: (s) => setState(() => _showMobileChart = s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return _kBrand.withValues(alpha: 0.1);
                return null;
              }),
            ),
          ),
        ),
        Expanded(
          child: _showMobileChart ? _buildGanttPanel(rows) : _buildTablePanel(rows),
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
                () => _tableWidth = (tableW + d.delta.dx).clamp(320.0, maxTable)),
            onDoubleTap: () => setState(() => _tableWidth = _kGridWidth),
            child: Tooltip(
              message: 'Drag to resize · double-click to fit all columns',
              waitDuration: const Duration(milliseconds: 800),
              child: Container(
                width: _kSplitterW,
                color: Colors.grey.shade200,
                child: Center(
                  child: Container(width: 2, height: 32, color: Colors.grey.shade400),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: _buildGanttPanel(rows)),
      ],
    );
  }

  Widget _buildTablePanel(List<_Row> rows) {
    final predCode = {for (final a in _activities) a.id: a.code};
    final context_ = _contextGroup(rows);
    final newDepth = _depthOf(context_?.id);

    return Column(
      children: [
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            notificationPredicate: (n) => n.depth == 0,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _kGridWidth,
                child: Column(
                  children: [
                    const _TableHeader(),
                    Expanded(
                      child: ListView.builder(
                        controller: _tableVertCtrl,
                        itemCount: rows.length + 1,
                        itemExtent: _kRowH,
                        itemBuilder: (ctx, i) {
                          if (i == rows.length) {
                            return _EditableRow(
                              key: _newRowKey,
                              depth: newDepth,
                              activities: _activities,
                              floors: _floors,
                              onSubmit: (d) => _create(d, context_),
                            );
                          }
                          final r = rows[i];
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
                            predecessorCode: predCode[a.predecessorId],
                            collapsed: _collapsed.contains(a.id),
                            onToggleCollapse: () => setState(() {
                              if (!_collapsed.remove(a.id)) _collapsed.add(a.id);
                            }),
                            onEdit: () => setState(() => _editingId = a.id),
                            onDelete: () => _deleteActivity(a),
                            onIndent: _indentTarget(a) == null ? null : () => _indent(a),
                            onOutdent: a.parentId == null ? null : () => _outdent(a),
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
          _ErrorBar(message: _gridError!, onClose: () => setState(() => _gridError = null)),
      ],
    );
  }

  Widget _buildGanttPanel(List<_Row> rows) {
    final dates = _ganttDateRange(rows);
    if (dates == null) {
      return const Center(
        child: Text('Add activities to see the Gantt chart',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }
    final (minDate, maxDate) = dates;
    final totalDays = maxDate.difference(minDate).inDays + 14;
    final ganttW = totalDays * _kPxPerDay;
    // +1 slot matches the table's inline new-entry row so scrolling stays aligned.
    final ganttH = (rows.length + 1) * _kRowH;

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
                painter: _GanttHeaderPainter(minDate: minDate, totalDays: totalDays),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _ganttVertCtrl,
                child: SizedBox(
                  width: ganttW,
                  height: ganttH,
                  child: CustomPaint(
                    painter: _GanttBodyPainter(
                      rows: rows,
                      minDate: minDate,
                      totalDays: totalDays,
                      rowHeight: _kRowH,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        code: d.code,
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('New group'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kBrand, foregroundColor: Colors.white),
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
        await ScheduleApi.updateActivity(a.id, name: d.name, code: d.code);
      } else {
        await ScheduleApi.updateActivity(
          a.id,
          name: d.name,
          code: d.code,
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
    final siblings = _childrenByParent()[_byId.containsKey(a.parentId) ? a.parentId : null] ?? [];
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
      await ScheduleApi.updateActivity(a.id, parentId: parentId, clearParent: parentId == null);
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
        content: Text(a.isGroup
            ? 'Delete group "${a.name}"? It must be empty first.'
            : 'Delete "${a.name}"? Other activities depending on it must be unlinked first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
            .map((p) => DropdownMenuItem<int?>(
                  value: p.id,
                  child: Text(p.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ))
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

  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}
