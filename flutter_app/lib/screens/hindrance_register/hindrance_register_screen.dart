import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/project_api.dart';
import '../../services/hindrance_api.dart';

const Color _kBrand = Color(0xFF0066CC);
const Color _kError = Color(0xFFD32F2F);

const List<String> _kTypes = ['weather', 'drawing', 'material', 'labour', 'client', 'other'];

class HindranceRegisterScreen extends StatefulWidget {
  const HindranceRegisterScreen({super.key});

  @override
  State<HindranceRegisterScreen> createState() => _HindranceRegisterScreenState();
}

class _HindranceRegisterScreenState extends State<HindranceRegisterScreen> {
  List<Project> _projects = [];
  Project? _selectedProject;
  List<Hindrance> _hindrances = [];
  List<ActivityOption> _activityOptions = [];
  bool _loading = false;
  String? _error;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await ProjectApi.listProjects();
      if (mounted) setState(() => _projects = projects);
    } catch (_) {}
  }

  Future<void> _loadData() async {
    if (_selectedProject == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        HindranceApi.listHindrances(_selectedProject!.id),
        HindranceApi.activityOptions(_selectedProject!.id),
      ]);
      if (mounted) {
        setState(() {
          _hindrances = results[0] as List<Hindrance>;
          _activityOptions = results[1] as List<ActivityOption>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Hindrance> get _filteredHindrances {
    if (_statusFilter == 'all') return _hindrances;
    return _hindrances.where((h) => h.status == _statusFilter).toList();
  }

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
            child: const Icon(Icons.report_problem, color: _kBrand, size: 22),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hindrance Register',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
              Text('Track and manage project hindrances and delays',
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
                _hindrances = [];
                _activityOptions = [];
                _error = null;
              });
              _loadData();
            },
          ),
          const Spacer(),
          if (_selectedProject != null) ...[
            _StatusFilterChips(
              value: _statusFilter,
              onChanged: (v) => setState(() => _statusFilter = v),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBrand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showHindranceDialog(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Hindrance', style: TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_selectedProject == null) {
      return _EmptyState(
        icon: Icons.report_problem_outlined,
        title: 'No project selected',
        subtitle: _projects.isEmpty
            ? 'No projects yet. Ask an administrator to create a project.'
            : 'Select a project above to view its hindrance register.',
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
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    final items = _filteredHindrances;
    if (items.isEmpty) {
      return _EmptyState(
        icon: Icons.check_circle_outline,
        title: _statusFilter == 'all'
            ? 'No hindrances recorded'
            : 'No ${_statusFilter} hindrances',
        subtitle: _statusFilter == 'all'
            ? 'Click "Add Hindrance" to log the first one.'
            : 'Change the status filter to see other entries.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: items.map((h) => _HindranceCard(
          hindrance: h,
          onEdit: () => _showHindranceDialog(h),
          onDelete: () => _deleteHindrance(h),
          onToggleStatus: () => _toggleStatus(h),
        )).toList(),
      ),
    );
  }

  void _showHindranceDialog(Hindrance? existing) {
    showDialog(
      context: context,
      builder: (ctx) => _HindranceDialog(
        projectId: _selectedProject!.id,
        existing: existing,
        activityOptions: _activityOptions,
        onSaved: _loadData,
      ),
    );
  }

  Future<void> _toggleStatus(Hindrance h) async {
    final newStatus = h.status == 'open' ? 'closed' : 'open';
    try {
      await HindranceApi.updateHindrance(h.id, status: newStatus);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
              backgroundColor: _kError),
        );
      }
    }
  }

  Future<void> _deleteHindrance(Hindrance h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete hindrance?'),
        content: Text('Delete this "${h.type}" hindrance?'),
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
      await HindranceApi.deleteHindrance(h.id);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
              backgroundColor: _kError),
        );
      }
    }
  }
}

// ─── Hindrance card ───────────────────────────────────────────────────────────

class _HindranceCard extends StatelessWidget {
  final Hindrance hindrance;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleStatus;

  const _HindranceCard({
    required this.hindrance,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final h = hindrance;
    final isOpen = h.status == 'open';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOpen ? Colors.orange.shade200 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: isOpen
                  ? Colors.orange.shade50
                  : Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                _TypeChip(type: h.type),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(h.description,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                _StatusChip(status: h.status),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 18, color: Colors.grey.shade500),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'toggle') onToggleStatus();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          const Icon(Icons.edit_outlined, size: 16),
                          const SizedBox(width: 8),
                          const Text('Edit')
                        ])),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Row(children: [
                          Icon(
                              isOpen
                                  ? Icons.check_circle_outline
                                  : Icons.radio_button_unchecked,
                              size: 16),
                          const SizedBox(width: 8),
                          Text(isOpen ? 'Mark Closed' : 'Reopen')
                        ])),
                    PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 16, color: _kError),
                          const SizedBox(width: 8),
                          Text('Delete',
                              style: const TextStyle(color: _kError))
                        ])),
                  ],
                ),
              ],
            ),
          ),
          // Detail row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Wrap(
              spacing: 24,
              runSpacing: 6,
              children: [
                if (h.raisedOn != null) _Detail('Raised', _fmtDate(h.raisedOn!)),
                if (h.startDate != null) _Detail('From', _fmtDate(h.startDate!)),
                if (h.endDate != null) _Detail('To', _fmtDate(h.endDate!)),
                if (h.delayDays != null) _Detail('Delay', '${h.delayDays} day(s)'),
                if (h.activityCode != null)
                  _Detail('Activity', '${h.activityCode} – ${h.activityName ?? ''}'),
                if (h.raisedBy != null) _Detail('By', h.raisedBy!),
              ],
            ),
          ),
          if (h.remarks != null && h.remarks!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Remarks: ${h.remarks}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
        ],
      ),
    );
  }

  String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;

  const _Detail(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
              text: '$label: ',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          TextSpan(
              text: value,
              style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }
}

// ─── Hindrance create / edit dialog ──────────────────────────────────────────

class _HindranceDialog extends StatefulWidget {
  final int projectId;
  final Hindrance? existing;
  final List<ActivityOption> activityOptions;
  final VoidCallback onSaved;

  const _HindranceDialog({
    required this.projectId,
    this.existing,
    required this.activityOptions,
    required this.onSaved,
  });

  @override
  State<_HindranceDialog> createState() => _HindranceDialogState();
}

class _HindranceDialogState extends State<_HindranceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _remarks;
  late final TextEditingController _delayDays;
  late String _type;
  late String _status;
  int? _activityId;
  DateTime? _raisedOn;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _description = TextEditingController(text: e?.description ?? '');
    _remarks = TextEditingController(text: e?.remarks ?? '');
    _delayDays =
        TextEditingController(text: e?.delayDays?.toString() ?? '');
    _type = e?.type ?? _kTypes.first;
    _status = e?.status ?? 'open';
    _activityId = e?.activityId;
    _raisedOn = e?.raisedOn != null ? DateTime.tryParse(e!.raisedOn!) : null;
    _startDate = e?.startDate != null ? DateTime.tryParse(e!.startDate!) : null;
    _endDate = e?.endDate != null ? DateTime.tryParse(e!.endDate!) : null;
  }

  @override
  void dispose() {
    _description.dispose();
    _remarks.dispose();
    _delayDays.dispose();
    super.dispose();
  }

  String _toIso(DateTime? d) => d != null
      ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
      : '';

  Future<void> _pick(String which) async {
    DateTime initial;
    switch (which) {
      case 'raised':
        initial = _raisedOn ?? DateTime.now();
      case 'start':
        initial = _startDate ?? DateTime.now();
      default:
        initial = _endDate ?? DateTime.now();
    }
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: _kBrand)),
        child: child!,
      ),
    );
    if (d == null) return;
    setState(() {
      switch (which) {
        case 'raised':
          _raisedOn = d;
        case 'start':
          _startDate = d;
        default:
          _endDate = d;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.existing == null) {
        await HindranceApi.createHindrance(
          projectId: widget.projectId,
          raisedOn: _toIso(_raisedOn).isEmpty ? null : _toIso(_raisedOn),
          type: _type,
          description: _description.text.trim(),
          activityId: _activityId,
          startDate: _toIso(_startDate).isEmpty ? null : _toIso(_startDate),
          endDate: _toIso(_endDate).isEmpty ? null : _toIso(_endDate),
          delayDays: _delayDays.text.trim().isEmpty
              ? null
              : int.tryParse(_delayDays.text.trim()),
          status: _status,
          remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
        );
      } else {
        await HindranceApi.updateHindrance(
          widget.existing!.id,
          raisedOn: _toIso(_raisedOn).isEmpty ? null : _toIso(_raisedOn),
          type: _type,
          description: _description.text.trim(),
          activityId: _activityId,
          clearActivity: _activityId == null && widget.existing!.activityId != null,
          startDate: _toIso(_startDate).isEmpty ? null : _toIso(_startDate),
          endDate: _toIso(_endDate).isEmpty ? null : _toIso(_endDate),
          delayDays: _delayDays.text.trim().isEmpty
              ? null
              : int.tryParse(_delayDays.text.trim()),
          status: _status,
          remarks: _remarks.text.trim(),
        );
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Hindrance' : 'Edit Hindrance'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) _ErrorBox(message: _error!),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _type,
                        decoration: const InputDecoration(
                            labelText: 'Type *',
                            border: OutlineInputBorder(),
                            isDense: true),
                        items: _kTypes
                            .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(_capitalize(t),
                                    style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (v) => setState(() => _type = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _status,
                        decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                            isDense: true),
                        items: ['open', 'closed']
                            .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(_capitalize(s),
                                    style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (v) => setState(() => _status = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Description *',
                      border: OutlineInputBorder(),
                      isDense: true),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _DateField(label: 'Raised On', date: _raisedOn, onTap: () => _pick('raised'))),
                    const SizedBox(width: 12),
                    Expanded(child: _DateField(label: 'From Date', date: _startDate, onTap: () => _pick('start'))),
                    const SizedBox(width: 12),
                    Expanded(child: _DateField(label: 'To Date', date: _endDate, onTap: () => _pick('end'))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int?>(
                        value: _activityId,
                        decoration: const InputDecoration(
                            labelText: 'Linked Activity (optional)',
                            border: OutlineInputBorder(),
                            isDense: true),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('None',
                                  style: TextStyle(fontSize: 13))),
                          ...widget.activityOptions.map((a) =>
                              DropdownMenuItem<int?>(
                                  value: a.id,
                                  child: Text('${a.code} – ${a.name}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13)))),
                        ],
                        onChanged: (v) => setState(() => _activityId = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _delayDays,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                            labelText: 'Delay (d)',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarks,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Remarks (optional)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kBrand),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(widget.existing == null ? 'Add' : 'Save',
                  style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ─── Reusable small widgets ───────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateField({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 14),
        ),
        child: Text(
          date != null
              ? '${date!.day.toString().padLeft(2, '0')}/${date!.month.toString().padLeft(2, '0')}/${date!.year}'
              : '—',
          style: TextStyle(
              fontSize: 13,
              color: date != null ? Colors.black87 : Colors.grey.shade400),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  static const _colors = {
    'weather': Color(0xFF1565C0),
    'drawing': Color(0xFF6A1B9A),
    'material': Color(0xFF2E7D32),
    'labour': Color(0xFFF57F17),
    'client': Color(0xFFBF360C),
    'other': Color(0xFF37474F),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[type] ?? const Color(0xFF37474F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '${type[0].toUpperCase()}${type.substring(1)}',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isOpen = status == 'open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOpen
            ? Colors.orange.shade100
            : const Color(0xFF2E7D32).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isOpen ? 'Open' : 'Closed',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isOpen ? Colors.orange.shade800 : const Color(0xFF2E7D32),
        ),
      ),
    );
  }
}

class _StatusFilterChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _StatusFilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'all', label: Text('All')),
        ButtonSegment(value: 'open', label: Text('Open')),
        ButtonSegment(value: 'closed', label: Text('Closed')),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

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
          Text(title,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(message, style: const TextStyle(color: _kError, fontSize: 13)),
    );
  }
}
