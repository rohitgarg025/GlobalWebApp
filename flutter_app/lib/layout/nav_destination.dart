import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// A single navigation destination in the sidebar.
class NavDestination {
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String? badge;
  final bool enabled;
  final String? requiredModule;
  final bool requiredAdmin;

  const NavDestination({
    required this.id,
    required this.label,
    required this.icon,
    IconData? activeIcon,
    this.badge,
    this.enabled = true,
    this.requiredModule,
    this.requiredAdmin = false,
  }) : activeIcon = activeIcon ?? icon;
}

/// A section group label in the sidebar.
class NavSection {
  final String title;
  final List<NavDestination> destinations;

  const NavSection({required this.title, required this.destinations});
}

/// Navigation filtered to what the signed-in user's role allows.
List<NavSection> get appNavSections {
  final modules = AuthService.instance.modules;
  final isAdmin = AuthService.instance.isAdmin;
  return _allNavSections
      .map((s) => NavSection(
            title: s.title,
            destinations: s.destinations
                .where((d) =>
                    (d.requiredModule == null || modules.contains(d.requiredModule)) &&
                    (!d.requiredAdmin || isAdmin))
                .toList(),
          ))
      .where((s) => s.destinations.isNotEmpty)
      .toList();
}

/// The full sidebar navigation config — add new modules here.
final List<NavSection> _allNavSections = [
  const NavSection(
    title: 'MAIN',
    destinations: [
      NavDestination(
        id: 'dashboard',
        label: 'Dashboard',
        icon: Icons.grid_view_outlined,
        activeIcon: Icons.grid_view_rounded,
      ),
    ],
  ),
  const NavSection(
    title: 'MODULES',
    destinations: [
      NavDestination(
        id: 'report_transformer',
        label: 'Report Transformer',
        icon: Icons.assessment_outlined,
        activeIcon: Icons.assessment,
        requiredModule: 'report_transformer',
      ),
      NavDestination(
        id: 'quantity_sheet',
        label: 'Quantity Sheet',
        icon: Icons.grid_on_outlined,
        activeIcon: Icons.grid_on,
        requiredModule: 'quantity_sheet',
      ),
      NavDestination(
        id: 'project_schedule',
        label: 'Project Schedule',
        icon: Icons.timeline_outlined,
        activeIcon: Icons.timeline,
        requiredModule: 'project_schedule',
      ),
      NavDestination(
        id: 'hindrance_register',
        label: 'Hindrance Register',
        icon: Icons.report_problem_outlined,
        activeIcon: Icons.report_problem,
        requiredModule: 'hindrance_register',
      ),
    ],
  ),
  const NavSection(
    title: 'ADMINISTRATION',
    destinations: [
      NavDestination(
        id: 'user_management',
        label: 'User Management',
        icon: Icons.manage_accounts_outlined,
        activeIcon: Icons.manage_accounts,
        requiredModule: 'user_management',
      ),
      NavDestination(
        id: 'project_master',
        label: 'Project Master',
        icon: Icons.apartment_outlined,
        activeIcon: Icons.apartment,
        requiredAdmin: true,
      ),
    ],
  ),
];
