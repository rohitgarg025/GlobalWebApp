import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/users_api.dart';

const Color _kBrand = Color(0xFF0066CC);

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<ManagedUser> _users = [];
  List<Role> _roles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([UsersApi.listUsers(), UsersApi.listRoles()]);
      setState(() {
        _users = results[0] as List<ManagedUser>;
        _roles = results[1] as List<Role>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('User Management',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _kBrand)),
                    Text('Assign roles and control module access',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const Icon(Icons.refresh, color: _kBrand),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: _kBrand,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _kBrand,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Users'),
            Tab(text: 'Roles'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _UsersTab(
                          users: _users,
                          roles: _roles,
                          onAssign: _assignRole,
                        ),
                        _RolesTab(
                          roles: _roles,
                          onCreate: _createRole,
                          onUpdate: _updateRole,
                          onDelete: _deleteRole,
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Future<void> _assignRole(ManagedUser user, Role role) async {
    try {
      await UsersApi.assignRole(user.id, role.id);
      _snack('${user.email} is now "${role.name}"');
      await _load();
      // If we changed our own role, refresh nav immediately
      if (user.email == AuthService.instance.user?.email) {
        await AuthService.instance.refreshProfile();
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _createRole(String name, List<String> modules) async {
    try {
      await UsersApi.createRole(name, modules);
      _snack('Role "$name" created');
      await _load();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _updateRole(Role role, String name, List<String> modules) async {
    try {
      await UsersApi.updateRole(role.id,
          name: role.isSystem ? null : name, modules: modules);
      _snack('Role updated');
      await _load();
      await AuthService.instance.refreshProfile();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _deleteRole(Role role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete role?'),
        content: Text('Delete the role "${role.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await UsersApi.deleteRole(role.id);
      _snack('Role "${role.name}" deleted');
      await _load();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }
}

// ─── Users tab ───────────────────────────────────────────────────────────────

class _UsersTab extends StatelessWidget {
  final List<ManagedUser> users;
  final List<Role> roles;
  final Future<void> Function(ManagedUser, Role) onAssign;

  const _UsersTab(
      {required this.users, required this.roles, required this.onAssign});

  String _formatLastLogin(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const Center(
          child: Text('No users have signed in yet.',
              style: TextStyle(color: Colors.grey)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 360),
              child: DataTable(
                headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w700, color: _kBrand, fontSize: 13),
                columns: const [
                  DataColumn(label: Text('User')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Modules')),
                  DataColumn(label: Text('Last Login (UTC)')),
                ],
                rows: users.map((u) {
                  final isSelf = u.email == AuthService.instance.user?.email;
                  return DataRow(cells: [
                    DataCell(Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: _kBrand.withValues(alpha: 0.12),
                          backgroundImage: u.picture != null
                              ? NetworkImage(u.picture!)
                              : null,
                          child: u.picture == null
                              ? const Icon(Icons.person_outline,
                                  size: 14, color: _kBrand)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(u.name ?? '—'),
                        if (isSelf)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kBrand.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('You',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _kBrand)),
                            ),
                          ),
                      ],
                    )),
                    DataCell(Text(u.email)),
                    DataCell(
                      DropdownButton<int>(
                        value: roles
                            .firstWhere((r) => r.name == u.role,
                                orElse: () => roles.first)
                            .id,
                        underline: const SizedBox.shrink(),
                        items: roles
                            .map((r) => DropdownMenuItem(
                                value: r.id, child: Text(r.name)))
                            .toList(),
                        onChanged: (roleId) {
                          if (roleId == null) return;
                          final role = roles.firstWhere((r) => r.id == roleId);
                          if (role.name != u.role) onAssign(u, role);
                        },
                      ),
                    ),
                    DataCell(Text(
                      u.modules
                          .map((m) => kModuleLabels[m] ?? m)
                          .join(', '),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    )),
                    DataCell(Text(_formatLastLogin(u.lastLoginAt))),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Roles tab ───────────────────────────────────────────────────────────────

class _RolesTab extends StatelessWidget {
  final List<Role> roles;
  final Future<void> Function(String name, List<String> modules) onCreate;
  final Future<void> Function(Role, String name, List<String> modules) onUpdate;
  final Future<void> Function(Role) onDelete;

  const _RolesTab({
    required this.roles,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
  });

  Future<void> _openRoleDialog(BuildContext context, {Role? existing}) async {
    final result = await showDialog<(String, List<String>)>(
      context: context,
      builder: (ctx) => _RoleDialog(existing: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await onCreate(result.$1, result.$2);
    } else {
      await onUpdate(existing, result.$1, result.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kBrand),
            onPressed: () => _openRoleDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Role'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: roles.map((role) {
              return Card(
                child: Container(
                  width: 300,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            role.isSystem
                                ? Icons.shield_outlined
                                : Icons.badge_outlined,
                            size: 18,
                            color: _kBrand,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(role.name,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                          if (role.isSystem)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('System',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade600)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...kModuleLabels.entries.map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  role.modules.contains(e.key)
                                      ? Icons.check_circle
                                      : Icons.remove_circle_outline,
                                  size: 16,
                                  color: role.modules.contains(e.key)
                                      ? Colors.green.shade600
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(width: 8),
                                Text(e.value,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: role.modules.contains(e.key)
                                            ? Colors.black87
                                            : Colors.grey.shade500)),
                              ],
                            ),
                          )),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                _openRoleDialog(context, existing: role),
                            child: const Text('Edit'),
                          ),
                          if (!role.isSystem)
                            TextButton(
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red),
                              onPressed: () => onDelete(role),
                              child: const Text('Delete'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _RoleDialog extends StatefulWidget {
  final Role? existing;

  const _RoleDialog({this.existing});

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final Set<String> _selected = {...?widget.existing?.modules};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = widget.existing?.isSystem ?? false;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New Role' : 'Edit Role'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              enabled: !isSystem,
              decoration: InputDecoration(
                labelText: 'Role name',
                helperText: isSystem ? 'System roles cannot be renamed' : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Accessible modules',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ...kModuleLabels.entries.map((e) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(e.value),
                  value: _selected.contains(e.key),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(e.key);
                    } else {
                      _selected.remove(e.key);
                    }
                  }),
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kBrand),
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, (name, _selected.toList()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
