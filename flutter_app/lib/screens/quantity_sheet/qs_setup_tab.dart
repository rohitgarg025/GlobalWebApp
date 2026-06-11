import 'package:flutter/material.dart';

import '../../models/quantity_sheet/qs_models.dart';
import '../../services/quantity_sheet_api.dart';
import 'qs_widgets.dart';

class QsSetupTab extends StatefulWidget {
  const QsSetupTab({super.key});

  @override
  State<QsSetupTab> createState() => _QsSetupTabState();
}

class _QsSetupTabState extends State<QsSetupTab> {
  List<QsProject> _projects = [];
  List<QsActivity> _activities = [];
  QsProject? _selectedProject;
  List<QsFloor> _floors = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = await QsApi.listProjects();
      final activities = await QsApi.listActivities();
      if (mounted) {
        setState(() {
          _projects = projects;
          _activities = activities;
          _loading = false;
          // Re-select if still valid
          if (_selectedProject != null) {
            _selectedProject = projects.cast<QsProject?>().firstWhere(
                  (p) => p?.id == _selectedProject!.id,
                  orElse: () => null,
                );
          }
        });
        if (_selectedProject != null) _loadFloors();
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

  Future<void> _loadFloors() async {
    if (_selectedProject == null) return;
    try {
      final floors = await QsApi.listFloors(_selectedProject!.id);
      if (mounted) setState(() => _floors = floors);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingCenter(message: 'Loading setup data…');
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _loadAll);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _projectsCard()),
          const SizedBox(width: 16),
          Expanded(child: _activitiesCard()),
          const SizedBox(width: 16),
          Expanded(child: _floorsCard()),
        ],
      ),
    );
  }

  // ── Projects ───────────────────────────────────────────────────────────────

  Widget _projectsCard() {
    return _SetupCard(
      title: 'Projects',
      icon: Icons.apartment_outlined,
      onAdd: _showAddProjectDialog,
      children: _projects.isEmpty
          ? [_emptyRow('No projects yet')]
          : _projects
              .map((p) => _SetupRow(
                    label: p.name,
                    selected: _selectedProject?.id == p.id,
                    onTap: () {
                      setState(() {
                        _selectedProject = p;
                        _floors = [];
                      });
                      _loadFloors();
                    },
                    onDelete: () => _deleteProject(p),
                  ))
              .toList(),
    );
  }

  Future<void> _showAddProjectDialog() async {
    final name = await _showTextDialog('Add Project', 'Project name');
    if (name == null || name.isEmpty) return;
    try {
      await QsApi.createProject(name);
      _loadAll();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _deleteProject(QsProject p) async {
    final ok = await _confirm('Delete project "${p.name}"?',
        'All floors and entries for this project will be deleted.');
    if (!ok) return;
    try {
      await QsApi.deleteProject(p.id);
      if (_selectedProject?.id == p.id) setState(() => _selectedProject = null);
      _loadAll();
    } catch (e) {
      _showError(e.toString());
    }
  }

  // ── Activities ─────────────────────────────────────────────────────────────

  Widget _activitiesCard() {
    return _SetupCard(
      title: 'Activities',
      icon: Icons.construction_outlined,
      onAdd: _showAddActivityDialog,
      children: _activities.isEmpty
          ? [_emptyRow('No activities yet')]
          : _activities
              .map((a) => _SetupRow(
                    label: a.name,
                    subtitle: a.unit,
                    onDelete: () => _deleteActivity(a),
                  ))
              .toList(),
    );
  }

  Future<void> _showAddActivityDialog() async {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Activity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl1,
              decoration: const InputDecoration(
                  labelText: 'Activity name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl2,
              decoration: const InputDecoration(
                  labelText: 'Unit (e.g. CUM, SQM, RMT)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBrand),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (result == true) {
      try {
        await QsApi.createActivity(ctrl1.text.trim(), ctrl2.text.trim().toUpperCase());
        _loadAll();
      } catch (e) {
        _showError(e.toString());
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl1.dispose();
      ctrl2.dispose();
    });
  }

  Future<void> _deleteActivity(QsActivity a) async {
    final ok = await _confirm('Delete activity "${a.name}"?',
        'Existing entries using this activity will be affected.');
    if (!ok) return;
    try {
      await QsApi.deleteActivity(a.id);
      _loadAll();
    } catch (e) {
      _showError(e.toString());
    }
  }

  // ── Floors ─────────────────────────────────────────────────────────────────

  Widget _floorsCard() {
    if (_selectedProject == null) {
      return _SetupCard(
        title: 'Floors',
        icon: Icons.layers_outlined,
        onAdd: null,
        children: [_emptyRow('Select a project first')],
      );
    }
    return _SetupCard(
      title: 'Floors — ${_selectedProject!.name}',
      icon: Icons.layers_outlined,
      onAdd: _showAddFloorDialog,
      children: _floors.isEmpty
          ? [_emptyRow('No floors yet')]
          : _floors
              .asMap()
              .entries
              .map((e) => _SetupRow(
                    label: e.value.name,
                    subtitle: 'Order ${e.value.displayOrder}',
                    onDelete: () => _deleteFloor(e.value),
                  ))
              .toList(),
    );
  }

  Future<void> _showAddFloorDialog() async {
    final name = await _showTextDialog('Add Floor', 'Floor name (e.g. B2, GF, 1F, RF)');
    if (name == null || name.isEmpty) return;
    final order = _floors.isEmpty
        ? 0
        : _floors.map((f) => f.displayOrder).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await QsApi.createFloor(_selectedProject!.id, name, order);
      _loadFloors();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _deleteFloor(QsFloor f) async {
    final ok = await _confirm('Delete floor "${f.name}"?',
        'All entries for this floor will be deleted.');
    if (!ok) return;
    try {
      await QsApi.deleteFloor(f.id);
      _loadFloors();
    } catch (e) {
      _showError(e.toString());
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<String?> _showTextDialog(String title, String hint) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
              labelText: hint, border: const OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBrand),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    return result;
  }

  Future<bool> _confirm(String title, String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(msg, style: const TextStyle(fontSize: 13)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kError),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg.replaceFirst('Exception: ', '')),
          backgroundColor: kError),
    );
  }

  Widget _emptyRow(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      );
}

// ─── Shared UI components ─────────────────────────────────────────────────────

class _SetupCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onAdd;
  final List<Widget> children;

  const _SetupCard({
    required this.title,
    required this.icon,
    required this.onAdd,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: kBrand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                if (onAdd != null)
                  IconButton(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_circle_outline,
                        size: 20, color: kBrand),
                    tooltip: 'Add',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupRow extends StatefulWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _SetupRow({
    required this.label,
    this.subtitle,
    this.selected = false,
    this.onTap,
    required this.onDelete,
  });

  @override
  State<_SetupRow> createState() => _SetupRowState();
}

class _SetupRowState extends State<_SetupRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? kBrand.withValues(alpha: 0.08)
                : _hovered
                    ? Colors.grey.withValues(alpha: 0.05)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: widget.selected
                ? Border.all(color: kBrand.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: widget.selected ? kBrand : Colors.black87)),
                    if (widget.subtitle != null)
                      Text(widget.subtitle!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              if (_hovered || widget.selected)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: Icon(Icons.delete_outline,
                      size: 16, color: Colors.grey.shade400),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
