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
  List<QsActivity> _activities = [];
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
      final activities = await QsApi.listActivities();
      if (mounted) {
        setState(() {
          _activities = activities;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingCenter(message: 'Loading setup data…');
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _loadAll);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _activitiesCard(),
        ),
      ),
    );
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
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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

  // ── Helpers ────────────────────────────────────────────────────────────────

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
  final VoidCallback onDelete;

  const _SetupRow({
    required this.label,
    this.subtitle,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? Colors.grey.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label,
                      style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  if (widget.subtitle != null)
                    Text(widget.subtitle!,
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            if (_hovered)
              GestureDetector(
                onTap: widget.onDelete,
                child: Icon(Icons.delete_outline,
                    size: 16, color: Colors.grey.shade400),
              ),
          ],
        ),
      ),
    );
  }
}
