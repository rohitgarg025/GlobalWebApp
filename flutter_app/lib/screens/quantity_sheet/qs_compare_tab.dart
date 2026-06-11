import 'package:flutter/material.dart';

import '../../models/quantity_sheet/qs_models.dart';
import '../../services/quantity_sheet_api.dart';
import 'qs_widgets.dart';

class QsCompareTab extends StatefulWidget {
  const QsCompareTab({super.key});

  @override
  State<QsCompareTab> createState() => _QsCompareTabState();
}

class _QsCompareTabState extends State<QsCompareTab> {
  List<QsActivity> _activities = [];
  int? _activityId;
  String _month = _currentMonth();
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    try {
      final acts = await QsApi.listActivities();
      if (mounted) setState(() => _activities = acts);
    } catch (_) {}
  }

  Future<void> _loadComparison() async {
    if (_activityId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await QsApi.getComparison(_activityId!, _month);
      if (mounted) {
        setState(() {
          _result = result;
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

  String _fmt(double? v) {
    if (v == null) return '—';
    return v.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSelector(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          const Text('Activity',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _activityId,
            hint: const Text('Select activity', style: TextStyle(fontSize: 13)),
            underline: const SizedBox(),
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            items: _activities
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} (${a.unit})'),
                    ))
                .toList(),
            onChanged: (id) {
              setState(() => _activityId = id);
              _loadComparison();
            },
          ),
          const SizedBox(width: 24),
          const Text('Month',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final parts = _month.split('-');
              final initial = DateTime(int.parse(parts[0]), int.parse(parts[1]));
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                initialEntryMode: DatePickerEntryMode.input,
              );
              if (picked != null) {
                final m =
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
                setState(() => _month = m);
                if (_activityId != null) _loadComparison();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined,
                      size: 16, color: kBrand),
                  const SizedBox(width: 6),
                  Text(_month,
                      style: const TextStyle(fontSize: 13, color: Colors.black87)),
                ],
              ),
            ),
          ),
          const Spacer(),
          PrimaryButton(
            label: 'Compare',
            icon: Icons.compare_arrows_outlined,
            onPressed: _activityId != null ? _loadComparison : null,
            loading: _loading,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_activityId == null) {
      return const EmptyState(
        icon: Icons.compare_arrows_outlined,
        title: 'Select an activity',
        subtitle: 'Choose an activity and month to compare across all projects',
      );
    }
    if (_loading) return const LoadingCenter(message: 'Loading comparison…');
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _loadComparison);
    if (_result == null) return const SizedBox();

    final projects = _result!['projects'] as List;
    if (projects.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No projects',
        subtitle: 'Create projects in the Setup tab',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity: ${_result!['activity']['name']} (${_result!['activity']['unit']}) — $_month',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 16),
          ...projects.map((p) => _projectCard(p)),
        ],
      ),
    );
  }

  Widget _projectCard(Map<String, dynamic> proj) {
    final cells = proj['cells'] as List;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(proj['project'],
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          if (cells.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('No floors configured',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            )
          else
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
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Floor')),
                  DataColumn(label: Text('Total Est. Qty'), numeric: true),
                  DataColumn(label: Text('Est. Actual Till Date'), numeric: true),
                  DataColumn(label: Text('Actual Qty'), numeric: true),
                  DataColumn(label: Text('Status')),
                ],
                rows: cells.map<DataRow>((c) {
                  final overrun = c['overrun'] as bool? ?? false;
                  return DataRow(
                    color: WidgetStateProperty.all(
                        overrun ? const Color(0xFFFFC7CE).withValues(alpha: 0.3) : null),
                    cells: [
                      DataCell(Text(c['floor'])),
                      DataCell(Text(_fmt((c['total_estimated_qty'] as num?)?.toDouble()))),
                      DataCell(Text(_fmt(
                          (c['estimate_actual_qty_till_date'] as num?)?.toDouble()))),
                      DataCell(Text(
                        _fmt((c['actual_qty'] as num?)?.toDouble()),
                        style: TextStyle(
                          color: overrun ? const Color(0xFF9C0006) : null,
                          fontWeight: overrun ? FontWeight.w700 : null,
                        ),
                      )),
                      DataCell(
                        overrun
                            ? const Row(children: [
                                Icon(Icons.warning_amber,
                                    size: 14, color: Color(0xFFD32F2F)),
                                SizedBox(width: 4),
                                Text('Overrun',
                                    style: TextStyle(
                                        color: Color(0xFFD32F2F),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ])
                            : const Icon(Icons.check_circle_outline,
                                size: 14, color: Color(0xFF2E7D32)),
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
