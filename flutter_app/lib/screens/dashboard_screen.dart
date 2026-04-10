import 'package:flutter/material.dart';
import '../layout/nav_destination.dart';

const Color _kBrand = Color(0xFF0066CC);

class DashboardScreen extends StatelessWidget {
  final ValueChanged<String> onNavigate;

  const DashboardScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeBanner(),
          const SizedBox(height: 32),
          _buildSectionTitle('Active Modules'),
          const SizedBox(height: 16),
          _buildModuleGrid(context, enabled: true),
          const SizedBox(height: 32),
          _buildSectionTitle('Coming Soon'),
          const SizedBox(height: 16),
          _buildModuleGrid(context, enabled: false),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0066CC), Color(0xFF0099FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome to Global Buildestate',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your all-in-one operations platform for construction project management.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => onNavigate('report_transformer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _kBrand,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Generate a Report',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Opacity(
            opacity: 0.2,
            child: Icon(Icons.domain,
                size: 100, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
    );
  }

  Widget _buildModuleGrid(BuildContext context, {required bool enabled}) {
    final allDests = appNavSections
        .expand((s) => s.destinations)
        .where((d) => d.id != 'dashboard' && d.enabled == enabled)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 700 ? 3 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.6,
          children: allDests
              .map((dest) => _ModuleCard(
                    dest: dest,
                    onTap: enabled ? () => onNavigate(dest.id) : null,
                  ))
              .toList(),
        );
      },
    );
  }
}

class _ModuleCard extends StatefulWidget {
  final NavDestination dest;
  final VoidCallback? onTap;

  const _ModuleCard({required this.dest, required this.onTap});

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  bool _hovered = false;

  static const List<Color> _cardColors = [
    Color(0xFF0066CC),
    Color(0xFF00897B),
    Color(0xFFE65100),
    Color(0xFF6A1B9A),
    Color(0xFF2E7D32),
  ];

  Color get _color {
    final idx = widget.dest.id.hashCode.abs() % _cardColors.length;
    return _cardColors[idx];
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? _color : Colors.grey.shade200,
              width: _hovered ? 1.5 : 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: _color.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: enabled ? 0.12 : 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.dest.icon,
                      color: enabled ? _color : Colors.grey.shade400,
                      size: 18,
                    ),
                  ),
                  if (widget.dest.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: enabled
                            ? _color.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.dest.badge!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: enabled ? _color : Colors.grey.shade400,
                        ),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.dest.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? Colors.black87
                          : Colors.grey.shade400,
                    ),
                  ),
                  if (enabled)
                    Text(
                      'Open →',
                      style: TextStyle(
                          fontSize: 11,
                          color: _color.withValues(alpha: 0.8)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
