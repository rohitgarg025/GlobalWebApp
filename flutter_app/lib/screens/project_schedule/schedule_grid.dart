part of 'project_schedule_screen.dart';

// ─── Grid layout ──────────────────────────────────────────────────────────────

class _Col {
  final String label;
  final double width;
  const _Col(this.label, this.width);
}

const _cType = _Col('TYPE', 86);
const _cName = _Col('NAME', 280);
const _cFloor = _Col('FLOOR', 96);
const _cDays = _Col('DAYS', 58);
const _cStart = _Col('START', 104);
const _cFinish = _Col('FINISH', 92);
const _cPred = _Col('PREDECESSOR', 150);
const _cLag = _Col('LAG', 52);
const _cQty = _Col('QTY', 72);
const _cUnit = _Col('UNIT', 62);
const _cActions = _Col('', 132);

const _kCols = [
  _cType, _cFloor, _cName, _cDays, _cStart, _cFinish,
  _cPred, _cLag, _cQty, _cUnit, _cActions,
];
final double _kGridWidth = _kCols.fold(0.0, (w, c) => w + c.width);

/// Left edge of the Name column (everything before it in [_kCols]).
final double _kNameLeft = _cType.width + _cFloor.width;

/// One visible line of the schedule tree.
class _Row {
  final PmActivity activity;
  final int depth;
  final bool hasChildren;

  /// False for groups with no activity anywhere beneath them (placeholder dates).
  final bool hasDates;
  const _Row(this.activity, this.depth, this.hasChildren, this.hasDates);
}

/// What the inline row hands back to the screen on Enter.
class _Draft {
  final String rowType;
  final String name;
  final int? floorId;
  final int? days;
  final DateTime? start;
  final int? predId;
  final int lag;
  final double? qty;
  final String? unit;

  const _Draft({
    required this.rowType,
    required this.name,
    this.floorId,
    this.days,
    this.start,
    this.predId,
    this.lag = 0,
    this.qty,
    this.unit,
  });

  bool get isGroup => rowType == 'group';
}

/// How an activity is identified to users (COD is internal-only): name, plus
/// floor so same-named activities on different floors stay distinguishable.
String _activityLabel(PmActivity a) =>
    a.floorName == null ? a.name : '${a.name} · ${a.floorName}';

String _fmtDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : _fmtDmy(d);
}

String _fmtDmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _isoOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Accepts dd/mm/yyyy, dd-mm-yyyy or dd.mm.yyyy (two-digit years → 20xx).
DateTime? _parseDmy(String text) {
  final m = RegExp(r'^\s*(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2}|\d{4})\s*$').firstMatch(text);
  if (m == null) return null;
  final d = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  var y = int.parse(m[3]!);
  if (y < 100) y += 2000;
  final dt = DateTime(y, mo, d);
  if (dt.day != d || dt.month != mo) return null;
  return dt;
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kGanttHeaderH,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          for (final c in _kCols)
            SizedBox(
              width: c.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(c.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                        letterSpacing: 0.4)),
              ),
            ),
        ],
      ),
    );
  }
}

BoxDecoration _rowDecoration(Color bg) => BoxDecoration(
      color: bg,
      border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
    );

// ─── Read-only row ────────────────────────────────────────────────────────────

/// What a row shows while another row is dragged over it.
enum _DropIndicator { none, before, after, invalid }

class _ActivityRow extends StatefulWidget {
  final _Row row;
  final String? predecessorLabel;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onIndent;
  final VoidCallback? onOutdent;

  /// Groups only: opens an entry row inside this group.
  final VoidCallback? onAddChild;

  /// Drag handle (a Draggable built by the screen, which owns the drop rules).
  final Widget dragHandle;

  final _DropIndicator indicator;

  /// Indent level for the insertion line (the level the row will land at).
  final int indicatorDepth;

  /// True while this row is the one being dragged.
  final bool isDragSource;

  const _ActivityRow({
    super.key,
    required this.row,
    required this.predecessorLabel,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onEdit,
    required this.onDelete,
    required this.onIndent,
    required this.onOutdent,
    required this.dragHandle,
    this.indicator = _DropIndicator.none,
    this.indicatorDepth = 0,
    this.isDragSource = false,
    this.onAddChild,
  });

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.row.activity;
    final g = a.isGroup;
    final bg = _hovered
        ? _kBrand.withValues(alpha: 0.04)
        : (g ? const Color(0xFFF3F5F9) : Colors.white);
    final muted = TextStyle(fontSize: 12, color: Colors.black54, fontWeight: g ? FontWeight.w600 : null);

    final lineLeft = _kNameLeft + 4 + widget.indicatorDepth * 16.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onDoubleTap: widget.onEdit,
        child: Stack(
          children: [
            Opacity(
              opacity: widget.isDragSource ? 0.35 : 1,
              child: Container(
          height: _kRowH,
          decoration: _rowDecoration(bg),
          child: Row(
            children: [
              SizedBox(
                width: _cType.width,
                child: Row(
                  children: [
                    widget.dragHandle,
                    _TypeChip(isGroup: g),
                  ],
                ),
              ),
              _text(_cFloor, a.floorName ?? '', muted),
              SizedBox(
                width: _cName.width,
                child: Padding(
                  padding: EdgeInsets.only(left: 4 + widget.row.depth * 16.0, right: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: g && widget.row.hasChildren
                            ? InkWell(
                                onTap: widget.onToggleCollapse,
                                child: Icon(
                                    widget.collapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                                    size: 18),
                              )
                            : null,
                      ),
                      Expanded(
                        child: Text(a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: g ? FontWeight.w700 : FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
              ),
              _text(_cDays, !widget.row.hasDates ? '' : '${a.durationDays}d', muted),
              _text(_cStart, !widget.row.hasDates ? '' : _fmtDate(a.startDate), muted),
              _text(_cFinish, !widget.row.hasDates ? '' : _fmtDate(a.finishDate), muted),
              _text(_cPred, widget.predecessorLabel ?? '', muted),
              _text(_cLag, a.predecessorId != null ? '${a.lagDays}d' : '', muted),
              _text(_cQty, a.quantity?.toString() ?? '', muted),
              _text(_cUnit, a.unit ?? '', muted),
              SizedBox(
                width: _cActions.width,
                child: _hovered
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _IconBtn(
                              icon: Icons.format_indent_decrease,
                              tooltip: 'Outdent (move out of group)',
                              onTap: widget.onOutdent),
                          _IconBtn(
                              icon: Icons.format_indent_increase,
                              tooltip: 'Indent (move into group above)',
                              onTap: widget.onIndent),
                          if (g)
                            _IconBtn(
                                icon: Icons.playlist_add,
                                tooltip: 'Add activity in this group',
                                color: _kBrand,
                                onTap: widget.onAddChild),
                          _IconBtn(icon: Icons.edit_outlined, tooltip: 'Edit', onTap: widget.onEdit),
                          _IconBtn(
                              icon: Icons.delete_outline,
                              tooltip: 'Delete',
                              color: _kError,
                              onTap: widget.onDelete),
                        ],
                      )
                    : null,
              ),
            ],
          ),
        ),
            ),
            if (widget.indicator == _DropIndicator.before ||
                widget.indicator == _DropIndicator.after)
              Positioned(
                left: lineLeft,
                right: 0,
                top: widget.indicator == _DropIndicator.before ? 0 : null,
                bottom: widget.indicator == _DropIndicator.after ? 0 : null,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _kBrand, width: 2),
                          color: Colors.white,
                        ),
                      ),
                      Expanded(child: Container(height: 2.5, color: _kBrand)),
                    ],
                  ),
                ),
              ),
            if (widget.indicator == _DropIndicator.invalid) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kError.withValues(alpha: 0.07),
                      border: Border.all(color: _kError, width: 1.5),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _kNameLeft + _cName.width - 172,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kError),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block, size: 12, color: _kError),
                          SizedBox(width: 4),
                          Text("Can't move here",
                              style: TextStyle(
                                  fontSize: 10, color: _kError, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(_Col c, Widget child) => SizedBox(
        width: c.width,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Align(alignment: Alignment.centerLeft, child: child)),
      );

  Widget _text(_Col c, String v, TextStyle style) => _cell(
        c,
        Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      );
}

class _TypeChip extends StatelessWidget {
  final bool isGroup;
  const _TypeChip({required this.isGroup});

  @override
  Widget build(BuildContext context) {
    final color = isGroup ? _kGroup : _kBrand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(isGroup ? 'Group' : 'Activity',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ─── Inline editable row (new entry, or editing an existing row) ─────────────

class _EditableRow extends StatefulWidget {
  final PmActivity? existing;
  final int depth;
  final List<PmActivity> activities;
  final List<ProjectFloor> floors;

  /// Returns true when saved; the screen shows any server error itself.
  final Future<bool> Function(_Draft draft) onSubmit;
  final VoidCallback? onCancel;

  /// Set when the row was opened from a group's "add activity" action.
  final String? groupName;

  const _EditableRow({
    super.key,
    this.existing,
    this.groupName,
    required this.depth,
    required this.activities,
    required this.floors,
    required this.onSubmit,
    this.onCancel,
  });

  @override
  State<_EditableRow> createState() => _EditableRowState();
}

class _EditableRowState extends State<_EditableRow> {
  final _nameFocus = FocusNode();
  final _name = TextEditingController();
  final _days = TextEditingController();
  final _start = TextEditingController();
  final _lag = TextEditingController();
  final _qty = TextEditingController();
  final _unit = TextEditingController();
  String _type = 'activity';
  int? _floorId;
  int? _predId;
  Set<String> _missing = {};
  bool _saving = false;

  bool get _isNew => widget.existing == null;
  bool get _isGroup => _type == 'group';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.rowType;
      _name.text = e.name;
      _floorId = e.floorId;
      _days.text = '${e.durationDays}';
      _start.text = _fmtDate(e.startDate);
      _predId = e.predecessorId;
      _lag.text = e.lagDays == 0 ? '' : '${e.lagDays}';
      _qty.text = e.quantity?.toString() ?? '';
      _unit.text = e.unit ?? '';
    }
    if (e != null || widget.groupName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _days, _start, _lag, _qty, _unit]) {
      c.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  void focusName() => _nameFocus.requestFocus();

  void _clear() {
    setState(() {
      for (final c in [_name, _days, _start, _lag, _qty, _unit]) {
        c.clear();
      }
      _type = 'activity';
      _predId = null;
      _missing = {};
      // Floor is kept: consecutive entries are usually for the same floor.
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _parseDmy(_start.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _kBrand)),
        child: child!,
      ),
    );
    if (d != null) setState(() => _start.text = _fmtDmy(d));
  }

  Future<void> _submit() async {
    if (_saving) return;
    final missing = <String>{};
    if (_name.text.trim().isEmpty) missing.add('name');
    final days = int.tryParse(_days.text.trim());
    final start = _parseDmy(_start.text);
    if (!_isGroup) {
      if (_floorId == null) missing.add('floor');
      if (days == null || days < 1) missing.add('days');
      if (start == null) missing.add('start');
    }
    if (_qty.text.trim().isNotEmpty && double.tryParse(_qty.text.trim()) == null) {
      missing.add('qty');
    }
    setState(() => _missing = missing);
    if (missing.isNotEmpty) return;

    setState(() => _saving = true);
    final ok = await widget.onSubmit(_Draft(
      rowType: _type,
      name: _name.text.trim(),
      floorId: _isGroup ? null : _floorId,
      days: _isGroup ? null : days,
      start: _isGroup ? null : start,
      predId: _isGroup ? null : _predId,
      lag: int.tryParse(_lag.text.trim()) ?? 0,
      qty: _isGroup || _qty.text.trim().isEmpty ? null : double.parse(_qty.text.trim()),
      unit: _isGroup || _unit.text.trim().isEmpty ? null : _unit.text.trim().toUpperCase(),
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok && _isNew) {
      _clear();
      // The reload moves this row down a slot; refocus after that frame or the
      // web text-input connection is lost and keystrokes go nowhere.
      _nameFocus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocus.requestFocus();
      });
    }
  }

  void _cancel() {
    // Entry rows opened from a group close on Esc; the bottom row just clears.
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      _clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final preds = widget.activities
        .where((a) => !a.isGroup && a.id != widget.existing?.id)
        .toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
      },
      child: Container(
        height: _kRowH,
        decoration: _rowDecoration(_isNew ? const Color(0xFFFFFDF2) : const Color(0xFFEFF6FF)),
        child: Row(
          children: [
            _box(
              _cType,
              DropdownButton<String>(
                value: _type,
                isDense: true,
                isExpanded: true,
                underline: const SizedBox(),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                items: const [
                  DropdownMenuItem(value: 'activity', child: Text('Activity')),
                  DropdownMenuItem(value: 'group', child: Text('Group')),
                ],
                // Changing type of a saved row isn't supported by the server.
                onChanged: _isNew ? (v) => setState(() => _type = v ?? 'activity') : null,
              ),
            ),
            _box(
              _cFloor,
              _isGroup
                  ? _dash()
                  : widget.floors.isEmpty
                      ? const Tooltip(
                          message: 'Add floors in Project Master',
                          child: Text('No floors', style: TextStyle(fontSize: 11, color: _kError)),
                        )
                      : DropdownButton<int>(
                          value: widget.floors.any((f) => f.id == _floorId) ? _floorId : null,
                          hint: const Text('Floor', style: TextStyle(fontSize: 12)),
                          isDense: true,
                          isExpanded: true,
                          underline: const SizedBox(),
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                          items: [
                            for (final f in widget.floors)
                              DropdownMenuItem(value: f.id, child: Text(f.name, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _floorId = v),
                        ),
              error: _missing.contains('floor'),
            ),
            SizedBox(
              width: _cName.width,
              child: Padding(
                // Matches the read-only row's indent + caret gutter so text lines up.
                padding: EdgeInsets.only(left: 18 + widget.depth * 16.0),
                child: _box(
                  _Col('', _cName.width - 18 - widget.depth * 16.0),
                  _input(_name,
                      focusNode: _nameFocus,
                      hint: !_isNew
                          ? null
                          : widget.groupName != null
                              ? 'New ${_isGroup ? 'sub-group' : 'activity'} in ${widget.groupName}…'
                              : (_isGroup ? 'New group name…' : 'New activity name…'),
                      key: 'name'),
                  error: _missing.contains('name'),
                ),
              ),
            ),
            _box(_cDays, _isGroup ? _dash() : _input(_days, hint: 'Days', digits: true, key: 'days'),
                error: _missing.contains('days')),
            _box(
              _cStart,
              _isGroup
                  ? _dash()
                  : _input(_start,
                      hint: 'dd/mm/yyyy',
                      key: 'start',
                      suffix: InkWell(
                        onTap: _pickDate,
                        child: const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
                      )),
              error: _missing.contains('start'),
            ),
            _box(_cFinish, _dash()),
            _box(
              _cPred,
              _isGroup
                  ? _dash()
                  : DropdownButton<int?>(
                      value: preds.any((a) => a.id == _predId) ? _predId : null,
                      hint: const Text('None', style: TextStyle(fontSize: 12)),
                      isDense: true,
                      isExpanded: true,
                      underline: const SizedBox(),
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('None')),
                        for (final a in preds)
                          DropdownMenuItem<int?>(
                            value: a.id,
                            child: Text(_activityLabel(a), overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _predId = v),
                    ),
            ),
            _box(_cLag, _isGroup || _predId == null ? _dash() : _input(_lag, hint: '0', digits: true, key: 'lag')),
            _box(_cQty, _isGroup ? _dash() : _input(_qty, hint: 'Qty', key: 'qty'),
                error: _missing.contains('qty')),
            _box(_cUnit, _isGroup ? _dash() : _input(_unit, hint: 'Unit', key: 'unit')),
            SizedBox(
              width: _cActions.width,
              child: _saving
                  ? const Center(
                      child: SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _IconBtn(
                            icon: Icons.check,
                            tooltip: _isNew ? 'Add row (Enter)' : 'Save (Enter)',
                            color: _kBrand,
                            onTap: _submit),
                        _IconBtn(
                            icon: Icons.close,
                            tooltip: widget.onCancel == null ? 'Clear (Esc)' : 'Close (Esc)',
                            onTap: _cancel),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dash() => Text('—', style: TextStyle(fontSize: 12, color: Colors.grey.shade400));

  Widget _box(_Col c, Widget child, {bool error = false}) {
    final box = Container(
      width: c.width,
      height: _kRowH,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border.all(
          color: error ? _kError : Colors.grey.shade200,
          width: error ? 1.5 : 0.5,
        ),
      ),
      child: child,
    );
    return error ? Tooltip(message: 'Required', child: box) : box;
  }

  Widget _input(
    TextEditingController ctrl, {
    required String key,
    FocusNode? focusNode,
    String? hint,
    bool digits = false,
    Widget? suffix,
  }) {
    return TextField(
      key: ValueKey('schedule-$key'),
      controller: ctrl,
      focusNode: focusNode,
      style: const TextStyle(fontSize: 12),
      keyboardType: digits ? TextInputType.number : TextInputType.text,
      inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      onChanged: (_) {
        if (_missing.contains(key)) setState(() => _missing.remove(key));
      },
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }
}

// ─── Drag helpers ─────────────────────────────────────────────────────────────

class _DropHint {
  final int targetId;
  final _DropIndicator indicator;
  final int depth;

  /// Insert position among the dragged row's siblings (valid drops only).
  final int? siblingIndex;
  final String? invalidGroupName;

  const _DropHint({
    required this.targetId,
    required this.indicator,
    required this.depth,
    this.siblingIndex,
    this.invalidGroupName,
  });
}

class _DragFeedback extends StatelessWidget {
  final PmActivity activity;
  const _DragFeedback({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(12, -16),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kBrand.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator, size: 14, color: _kBrand),
              const SizedBox(width: 6),
              _TypeChip(isGroup: activity.isGroup),
              const SizedBox(width: 6),
              Text(activity.name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = const Color(0xFF555555),
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: onTap == null ? Colors.grey.shade300 : color),
        ),
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _ErrorBar({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: _kError.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 15, color: _kError),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: _kError, fontSize: 12))),
          InkWell(onTap: onClose, child: const Icon(Icons.close, size: 14, color: _kError)),
        ],
      ),
    );
  }
}
