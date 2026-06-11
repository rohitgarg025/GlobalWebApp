import 'package:flutter/material.dart';

import '../../models/quantity_sheet/qs_models.dart';
import '../../services/quantity_sheet_api.dart';
import 'qs_widgets.dart';

class QsOverrunsTab extends StatefulWidget {
  const QsOverrunsTab({super.key});

  @override
  State<QsOverrunsTab> createState() => _QsOverrunsTabState();
}

class _QsOverrunsTabState extends State<QsOverrunsTab> {
  List<Map<String, dynamic>> _projects = [];
  int? _filterProjectId;
  List<QsOverrun> _overruns = [];
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
      final overruns = await QsApi.getOverruns(projectId: _filterProjectId);
      if (mounted) {
        setState(() {
          _projects = [
            <String, dynamic>{'id': null, 'name': 'All Projects'},
            ...projects.map((p) => <String, dynamic>{'id': p.id, 'name': p.name}),
          ];
          _overruns = overruns;
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

  String _fmt(double v) =>
      v.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          const Text('Project',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(width: 8),
          DropdownButton<int?>(
            value: _filterProjectId,
            underline: const SizedBox(),
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            items: _projects
                .map((p) => DropdownMenuItem<int?>(
                      value: p['id'],
                      child: Text(p['name']),
                    ))
                .toList(),
            onChanged: (id) {
              setState(() => _filterProjectId = id);
              _loadAll();
            },
          ),
          const Spacer(),
          if (_overruns.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_overruns.length} overrun${_overruns.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD32F2F)),
              ),
            ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Refresh'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey.shade300),
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingCenter(message: 'Loading overruns…');
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _loadAll);
    if (_overruns.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'No overruns',
        subtitle: 'All actual quantities are within estimates',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overruns — Actual Qty exceeds Total Estimated Qty',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800),
          ),
          const SizedBox(height: 4),
          Text(
            'Justification is required for all overruns at submission time.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F7FA)),
              headingTextStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
              dataTextStyle:
                  const TextStyle(fontSize: 12, color: Colors.black87),
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('Project')),
                DataColumn(label: Text('Month')),
                DataColumn(label: Text('Activity')),
                DataColumn(label: Text('Unit')),
                DataColumn(label: Text('Floor')),
                DataColumn(label: Text('Total Est. Qty'), numeric: true),
                DataColumn(label: Text('Actual Qty'), numeric: true),
                DataColumn(label: Text('Excess'), numeric: true),
                DataColumn(label: Text('Justification')),
              ],
              rows: _overruns.map((o) {
                return DataRow(
                  color: WidgetStateProperty.all(
                      const Color(0xFFFFC7CE).withValues(alpha: 0.25)),
                  cells: [
                    DataCell(Text(o.project,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text(o.month)),
                    DataCell(Text(o.activity)),
                    DataCell(Text(o.unit,
                        style: const TextStyle(color: Colors.grey))),
                    DataCell(Text(o.floor)),
                    DataCell(Text(_fmt(o.totalEstimatedQty))),
                    DataCell(Text(
                      _fmt(o.actualQty),
                      style: const TextStyle(
                          color: Color(0xFF9C0006),
                          fontWeight: FontWeight.w700),
                    )),
                    DataCell(Text(
                      '+${_fmt(o.excess)}',
                      style: const TextStyle(
                          color: Color(0xFFD32F2F),
                          fontWeight: FontWeight.w600),
                    )),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: o.justification?.isNotEmpty == true
                            ? Tooltip(
                                message: o.justification!,
                                child: Text(
                                  o.justification!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11, fontStyle: FontStyle.italic),
                                ),
                              )
                            : const Text(
                                'No justification provided',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFD32F2F),
                                    fontStyle: FontStyle.italic),
                              ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
