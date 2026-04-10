import 'package:flutter/material.dart';

import 'nav_destination.dart';
import '../screens/dashboard_screen.dart';
import '../screens/coming_soon_screen.dart';
import '../screens/report_transformer/step1_report_type_screen.dart';

/// Breakpoint below which the sidebar collapses into a hamburger drawer.
const double _kSidebarBreakpoint = 720;
const double _kSidebarWidth = 248;
const Color _kBrand = Color(0xFF0066CC);

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _activeId = 'dashboard';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Widget _buildContent() {
    switch (_activeId) {
      case 'dashboard':
        return DashboardScreen(
          onNavigate: (id) => setState(() => _activeId = id),
        );
      case 'report_transformer':
        // Each visit starts fresh at Step 1
        return const Step1ReportTypeScreen();
      default:
        // All "coming soon" modules
        final dest = appNavSections
            .expand((s) => s.destinations)
            .firstWhere((d) => d.id == _activeId,
                orElse: () => const NavDestination(
                    id: '', label: 'Unknown', icon: Icons.help_outline));
        return ComingSoonScreen(title: dest.label, icon: dest.icon);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= _kSidebarBreakpoint;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      // Mobile: overlay drawer
      drawer: isWide ? null : _SidebarContent(
        activeId: _activeId,
        onSelect: (id) {
          setState(() => _activeId = id);
          _scaffoldKey.currentState?.closeDrawer();
        },
      ),
      body: Row(
        children: [
          // Desktop: persistent sidebar
          if (isWide)
            _SidebarContent(
              activeId: _activeId,
              onSelect: (id) => setState(() => _activeId = id),
            ),
          // Main content area
          Expanded(
            child: Column(
              children: [
                // Mobile top app bar with hamburger
                if (!isWide)
                  _MobileTopBar(
                    activeId: _activeId,
                    onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sidebar ────────────────────────────────────────────────────────────────

class _SidebarContent extends StatelessWidget {
  final String activeId;
  final ValueChanged<String> onSelect;

  const _SidebarContent({required this.activeId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kSidebarWidth,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrand(),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: appNavSections
                    .map((section) => _SidebarSection(
                          section: section,
                          activeId: activeId,
                          onSelect: onSelect,
                        ))
                    .toList(),
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildBrand() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _kBrand,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.domain, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Global Buildestate',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kBrand,
                  ),
                ),
                Text(
                  'Operations Platform',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: _kBrand.withValues(alpha: 0.12),
            child: const Icon(Icons.person_outline, size: 16, color: _kBrand),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin User',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text('v1.0.0',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSection extends StatelessWidget {
  final NavSection section;
  final String activeId;
  final ValueChanged<String> onSelect;

  const _SidebarSection(
      {required this.section,
      required this.activeId,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            section.title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade400,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...section.destinations.map((dest) => _NavItem(
              dest: dest,
              isActive: activeId == dest.id,
              onTap: dest.enabled ? () => onSelect(dest.id) : null,
            )),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _NavItem extends StatefulWidget {
  final NavDestination dest;
  final bool isActive;
  final VoidCallback? onTap;

  const _NavItem(
      {required this.dest, required this.isActive, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final enabled = widget.onTap != null;

    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? _kBrand.withValues(alpha: 0.1)
                : _hovered
                    ? Colors.grey.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                active ? widget.dest.activeIcon : widget.dest.icon,
                size: 18,
                color: active
                    ? _kBrand
                    : enabled
                        ? Colors.grey.shade600
                        : Colors.grey.shade400,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.dest.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400,
                    color: active
                        ? _kBrand
                        : enabled
                            ? Colors.grey.shade800
                            : Colors.grey.shade400,
                  ),
                ),
              ),
              if (widget.dest.badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: active
                        ? _kBrand.withValues(alpha: 0.15)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.dest.badge!,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: active ? _kBrand : Colors.grey.shade500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mobile top bar ─────────────────────────────────────────────────────────

class _MobileTopBar extends StatelessWidget {
  final String activeId;
  final VoidCallback onMenuTap;

  const _MobileTopBar({required this.activeId, required this.onMenuTap});

  String get _title {
    for (final section in appNavSections) {
      for (final dest in section.destinations) {
        if (dest.id == activeId) return dest.label;
      }
    }
    return 'Global Buildestate';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: _kBrand),
            onPressed: onMenuTap,
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _kBrand,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.domain, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Text(
            _title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _kBrand,
            ),
          ),
        ],
      ),
    );
  }
}
