import 'package:flutter/material.dart';

/// A single navigation destination in the sidebar.
class NavDestination {
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String? badge; // e.g. "New", "Beta"
  final bool enabled;

  const NavDestination({
    required this.id,
    required this.label,
    required this.icon,
    IconData? activeIcon,
    this.badge,
    this.enabled = true,
  }) : activeIcon = activeIcon ?? icon;
}

/// A section group label in the sidebar.
class NavSection {
  final String title;
  final List<NavDestination> destinations;

  const NavSection({required this.title, required this.destinations});
}

/// The full sidebar navigation config — add new modules here.
final List<NavSection> appNavSections = [
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
      ),
      NavDestination(
        id: 'project_tracker',
        label: 'Project Tracker',
        icon: Icons.construction_outlined,
        activeIcon: Icons.construction,
        badge: 'Soon',
        enabled: false,
      ),
      NavDestination(
        id: 'budget_planner',
        label: 'Budget Planner',
        icon: Icons.account_balance_wallet_outlined,
        activeIcon: Icons.account_balance_wallet,
        badge: 'Soon',
        enabled: false,
      ),
      NavDestination(
        id: 'material_registry',
        label: 'Material Registry',
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2,
        badge: 'Soon',
        enabled: false,
      ),
    ],
  ),
  const NavSection(
    title: 'ANALYTICS',
    destinations: [
      NavDestination(
        id: 'insights',
        label: 'Insights',
        icon: Icons.bar_chart_outlined,
        activeIcon: Icons.bar_chart,
        badge: 'Soon',
        enabled: false,
      ),
      NavDestination(
        id: 'reports_history',
        label: 'Reports History',
        icon: Icons.history_outlined,
        activeIcon: Icons.history,
        badge: 'Soon',
        enabled: false,
      ),
    ],
  ),
];
