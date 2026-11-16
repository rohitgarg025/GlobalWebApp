import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/project_api.dart';

const Color _kBrand = Color(0xFF0066CC);
const Color _kError = Color(0xFFD32F2F);

class ProjectMasterScreen extends StatefulWidget {
  const ProjectMasterScreen({super.key});

  @override
  State<ProjectMasterScreen> createState() => _ProjectMasterScreenState();
}

class _ProjectMasterScreenState extends State<ProjectMasterScreen> {
  List<Project> _projects = [];
  bool _loading = false;
  String? _error;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = await ProjectApi.listProjects(includeArchived: _showArchived);
      if (mounted) setState(() => _projects = projects);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            child: const Icon(Icons.apartment, color: _kBrand, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Project Master',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                Text('Create and manage projects used across all modules',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Row(
            children: [
              _ArchiveToggle(
                value: _showArchived,
                onChanged: (v) {
                  setState(() => _showArchived = v);
                  _load();
                },
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showProjectDialog(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Project', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
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
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.apartment_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _showArchived ? 'No archived projects' : 'No active projects yet',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text('Click "New Project" to create the first one.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.hardEdge,
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.5),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1.8),
            4: FixedColumnWidth(90),
            5: FixedColumnWidth(160),
          },
          children: [
            _tableHeader(['Project Name', 'Code', 'Location', 'Client', 'Status', 'Actions']),
            ..._projects.map(_tableRow),
          ],
        ),
      ),
    );
  }

  TableRow _tableHeader(List<String> labels) {
    return TableRow(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      children: labels
          .map((l) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(l,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
              ))
          .toList(),
    );
  }

  TableRow _tableRow(Project p) {
    final isArchived = p.status == 'archived';
    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        color: isArchived ? Colors.grey.shade50 : Colors.white,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(p.name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isArchived ? Colors.grey : Colors.black87)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(p.code ?? '—',
              style: TextStyle(fontSize: 13, color: isArchived ? Colors.grey : Colors.black54)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(p.location ?? '—',
              style: TextStyle(fontSize: 13, color: isArchived ? Colors.grey : Colors.black54)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(p.clientName ?? '—',
              style: TextStyle(fontSize: 13, color: isArchived ? Colors.grey : Colors.black54)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: _StatusChip(status: p.status),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _IconBtn(
                icon: Icons.layers_outlined,
                tooltip: 'Manage Floors',
                onTap: () => _showFloorsDialog(p),
              ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.edit_outlined,
                tooltip: 'Edit',
                onTap: () => _showProjectDialog(p),
              ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                tooltip: isArchived ? 'Unarchive' : 'Archive',
                onTap: () => _toggleArchive(p),
              ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.delete_outline,
                tooltip: 'Delete',
                color: _kError,
                onTap: () => _deleteProject(p),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showProjectDialog(Project? existing) {
    showDialog(
      context: context,
      builder: (ctx) => _ProjectDialog(
        existing: existing,
        onSaved: _load,
      ),
    );
  }

  void _showFloorsDialog(Project p) {
    showDialog(
      context: context,
      builder: (ctx) => _FloorsDialog(project: p),
    );
  }

  Future<void> _toggleArchive(Project p) async {
    final isArchived = p.status == 'archived';
    try {
      await ProjectApi.updateProject(p.id, status: isArchived ? 'active' : 'archived');
      _load();
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

  Future<void> _deleteProject(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
            'Delete "${p.name}"? This cannot be undone.\nArchive it instead if it has existing data.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
      await ProjectApi.deleteProject(p.id);
      _load();
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

// ─── Project create / edit dialog ────────────────────────────────────────────

class _ProjectDialog extends StatefulWidget {
  final Project? existing;
  final VoidCallback onSaved;

  const _ProjectDialog({this.existing, required this.onSaved});

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _location;
  late final TextEditingController _client;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _code = TextEditingController(text: widget.existing?.code ?? '');
    _location = TextEditingController(text: widget.existing?.location ?? '');
    _client = TextEditingController(text: widget.existing?.clientName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _location.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.existing == null) {
        await ProjectApi.createProject(
          name: _name.text.trim(),
          code: _code.text.trim(),
          location: _location.text.trim(),
          clientName: _client.text.trim(),
        );
      } else {
        await ProjectApi.updateProject(
          widget.existing!.id,
          name: _name.text.trim(),
          code: _code.text.trim(),
          location: _location.text.trim(),
          clientName: _client.text.trim(),
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
      title: Text(widget.existing == null ? 'New Project' : 'Edit Project'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kError.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: _kError, fontSize: 13)),
                ),
              _field(_name, 'Project Name *', required: true),
              const SizedBox(height: 12),
              _field(_code, 'Code (e.g. GB-001)'),
              const SizedBox(height: 12),
              _field(_location, 'Location'),
              const SizedBox(height: 12),
              _field(_client, 'Client Name'),
            ],
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
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(widget.existing == null ? 'Create' : 'Save',
                  style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, {bool required = false}) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }
}

// ─── Floors dialog ───────────────────────────────────────────────────────────

class _FloorsDialog extends StatefulWidget {
  final Project project;
  const _FloorsDialog({required this.project});

  @override
  State<_FloorsDialog> createState() => _FloorsDialogState();
}

class _FloorsDialogState extends State<_FloorsDialog> {
  List<ProjectFloor> _floors = [];
  bool _loading = true;
  String? _error;
  final _addCtrl = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final floors = await ProjectApi.listFloors(widget.project.id);
      if (mounted) setState(() => _floors = floors);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addFloor() async {
    final name = _addCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _adding = true);
    try {
      await ProjectApi.createFloor(widget.project.id, name);
      _addCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
              backgroundColor: _kError),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _deleteFloor(ProjectFloor f) async {
    try {
      await ProjectApi.deleteFloor(f.id);
      await _load();
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

  Future<void> _move(int index, int direction) async {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= _floors.length) return;
    final reordered = List<ProjectFloor>.from(_floors);
    final tmp = reordered[index];
    reordered[index] = reordered[newIndex];
    reordered[newIndex] = tmp;
    setState(() => _floors = reordered);
    try {
      await ProjectApi.reorderFloors(
          widget.project.id, reordered.map((f) => f.id).toList());
    } catch (_) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.layers_outlined, size: 20, color: _kBrand),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Floors — ${widget.project.name}',
                style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: _kError, fontSize: 13)),
              ),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(color: _kBrand)))
            else if (_floors.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No floors yet. Add one below.',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: _floors.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final reordered = List<ProjectFloor>.from(_floors);
                    final item = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, item);
                    setState(() => _floors = reordered);
                    ProjectApi.reorderFloors(
                        widget.project.id, reordered.map((f) => f.id).toList());
                  },
                  itemBuilder: (ctx, i) {
                    final f = _floors[i];
                    return _FloorRow(
                      key: ValueKey(f.id),
                      floor: f,
                      index: i,
                      total: _floors.length,
                      onMoveUp: () => _move(i, -1),
                      onMoveDown: () => _move(i, 1),
                      onDelete: () => _deleteFloor(f),
                    );
                  },
                ),
              ),
            const Divider(height: 24),
            // Add floor row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    autofocus: false,
                    decoration: const InputDecoration(
                      hintText: 'Floor name (e.g. B2, GF, 1F, Terrace)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addFloor(),
                    inputFormatters: [LengthLimitingTextInputFormatter(30)],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _adding ? null : _addFloor,
                  child: _adding
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done')),
      ],
    );
  }
}

class _FloorRow extends StatelessWidget {
  final ProjectFloor floor;
  final int index;
  final int total;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  const _FloorRow({
    super.key,
    required this.floor,
    required this.index,
    required this.total,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.drag_handle, size: 18, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(floor.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            onPressed: index == 0 ? null : onMoveUp,
            tooltip: 'Move up',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            color: Colors.grey.shade600,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            onPressed: index == total - 1 ? null : onMoveDown,
            tooltip: 'Move down',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            color: Colors.grey.shade600,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            onPressed: onDelete,
            tooltip: 'Remove floor',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            color: _kError,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ─── Small reusable widgets ───────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Active' : 'Archived',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? const Color(0xFF2E7D32) : Colors.grey.shade500,
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
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
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _ArchiveToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ArchiveToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
          color: value ? _kBrand.withValues(alpha: 0.07) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.archive_outlined,
                size: 15, color: value ? _kBrand : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text('Show archived',
                style: TextStyle(
                    fontSize: 12,
                    color: value ? _kBrand : Colors.grey.shade600,
                    fontWeight: value ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
