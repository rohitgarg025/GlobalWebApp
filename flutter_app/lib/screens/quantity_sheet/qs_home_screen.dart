import 'package:flutter/material.dart';

import 'qs_entry_tab.dart';
import 'qs_view_tab.dart';
import 'qs_compare_tab.dart';
import 'qs_overruns_tab.dart';
import 'qs_setup_tab.dart';

const Color _kBrand = Color(0xFF0066CC);

class QsHomeScreen extends StatefulWidget {
  const QsHomeScreen({super.key});

  @override
  State<QsHomeScreen> createState() => _QsHomeScreenState();
}

class _QsHomeScreenState extends State<QsHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const _tabDefs = [
    (Icons.edit_note_outlined, 'Data Entry'),
    (Icons.table_chart_outlined, 'View / Export'),
    (Icons.compare_arrows_outlined, 'Compare'),
    (Icons.warning_amber_outlined, 'Overruns'),
    (Icons.settings_outlined, 'Setup'),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabDefs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              QsEntryTab(),
              QsViewTab(),
              QsCompareTab(),
              QsOverrunsTab(),
              QsSetupTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.grid_on, color: _kBrand, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quantity Sheet',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E)),
                    ),
                    Text(
                      'Track and audit construction quantities by project, activity and floor',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: _kBrand,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: _kBrand,
            indicatorWeight: 2.5,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            tabs: _tabDefs
                .map((t) => Tab(
                      child: Row(
                        children: [
                          Icon(t.$1, size: 16),
                          const SizedBox(width: 6),
                          Text(t.$2),
                        ],
                      ),
                    ))
                .toList(),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
        ],
      ),
    );
  }
}
