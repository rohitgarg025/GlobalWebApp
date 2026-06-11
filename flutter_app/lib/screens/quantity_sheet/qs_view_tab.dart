import 'package:flutter/material.dart';

import '../../models/quantity_sheet/qs_models.dart';
import '../../services/quantity_sheet_api.dart';
import '../../services/download_service.dart' show downloadFileOnWeb;
import 'qs_widgets.dart';

const double _kRowHeaderW = 220.0;
const double _kUnitW = 60.0;
const double _kCellW = 100.0;
const double _kRowH = 38.0;
const double _kHeaderH = 50.0;
const double _kSubHeaderH = 32.0;

class QsViewTab extends StatefulWidget {
  const QsViewTab({super.key});

  @override
  State<QsViewTab> createState() => _QsViewTabState();
}

class _QsViewTabState extends State<QsViewTab> {
  List<Map<String, dynamic>> _projects = [];
  int? _projectId;
  String _month = _currentMonth();
  QsProjectData? _data;
  bool _loading = false;
  String? _error;
  bool _exporting = false;

  final ScrollController _hScrollCtrl = ScrollController();

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await QsApi.listProjects();
      if (mounted) {
        setState(() {
          _projects = projects
              .map((p) => <String, dynamic>{'id': p.id, 'name': p.name})
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    if (_projectId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await QsApi.getProjectData(_projectId!, _month);
      if (mounted) {
        setState(() {
          _data = data;
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

  Future<void> _export() async {
    if (_projectId == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = await QsApi.exportExcel(_projectId!, _month);
      final projectName = _projects
          .firstWhere((p) => p['id'] == _projectId,
              orElse: () => <String, dynamic>{'name': 'project'})['name'] as String;
      downloadFileOnWeb(bytes, 'quantity_sheet_${projectName}_$_month.xlsx');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: kError),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
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
        QsSelector(
          projects: _projects,
          selectedProjectId: _projectId,
          selectedMonth: _month,
          onProjectChanged: (id) {
            setState(() => _projectId = id);
            _loadData();
          },
          onMonthChanged: (m) {
            setState(() => _month = m);
            if (_projectId != null) _loadData();
          },
          trailing: PrimaryButton(
            label: 'Download Excel',
            icon: Icons.download_outlined,
            onPressed: _data != null ? _export : null,
            loading: _exporting,
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_projectId == null) {
      return const EmptyState(
        icon: Icons.table_chart_outlined,
        title: 'Select a project',
        subtitle: 'Choose a project and month to view the quantity sheet',
      );
    }
    if (_loading) return const LoadingCenter(message: 'Loading…');
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _loadData);
    if (_data == null) return const SizedBox();
    if (_data!.floors.isEmpty || _data!.activities.isEmpty) {
      return const EmptyState(
        icon: Icons.info_outline,
        title: 'No data',
        subtitle: 'No floors or activities configured for this project',
      );
    }

    final hasData = _data!.cells.any((c) => c.estimateActualQtyTillDate != null);
    if (!hasData) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No entries for this month',
        subtitle: 'Submit data from the Data Entry tab first',
      );
    }

    return _buildGrid();
  }

  Widget _buildGrid() {
    final floors = _data!.floors;
    final acts = _data!.activities;
    final totalCols = _kRowHeaderW + _kUnitW + floors.length * 3 * _kCellW;

    return Scrollbar(
      controller: _hScrollCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _hScrollCtrl,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalCols,
          child: Column(
            children: [
              _buildColHeaders(floors),
              _buildSubHeaders(floors),
              Expanded(
                child: ListView.builder(
                  itemCount: acts.length,
                  itemBuilder: (_, i) => _buildRow(acts[i], floors, i),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColHeaders(List<QsFloor> floors) {
    return Container(
      height: _kHeaderH,
      color: const Color(0xFF0066CC),
      child: Row(
        children: [
          _hdr('Activity', _kRowHeaderW),
          _hdr('Unit', _kUnitW),
          ...floors.map((f) => _hdr(f.name, _kCellW * 3)),
        ],
      ),
    );
  }

  Widget _buildSubHeaders(List<QsFloor> floors) {
    return Container(
      height: _kSubHeaderH,
      color: const Color(0xFFD6E4F7),
      child: Row(
        children: [
          SizedBox(width: _kRowHeaderW),
          SizedBox(width: _kUnitW),
          ...floors.expand((_) => [
                _subHdr('Total Est.\n(Drawing)', _kCellW),
                _subHdr('Est. Actual\nTill Date', _kCellW),
                _subHdr('Actual Qty', _kCellW),
              ]),
        ],
      ),
    );
  }

  Widget _hdr(String text, double width) => SizedBox(
        width: width,
        child: Center(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      );

  Widget _subHdr(String text, double width) => SizedBox(
        width: width,
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _buildRow(QsActivity act, List<QsFloor> floors, int idx) {
    final bg = idx.isEven ? Colors.white : const Color(0xFFF8FAFC);
    return Container(
      height: _kRowH,
      color: bg,
      child: Row(
        children: [
          _label(act.name, _kRowHeaderW),
          _label(act.unit, _kUnitW, grey: true),
          ...floors.expand((floor) {
            final cell = _data!.cell(act.id, floor.id);
            final overrun = cell?.isOverrun ?? false;
            return [
              _cell(_fmt(cell?.totalEstimatedQty), _kCellW, isOverrun: false),
              _cell(_fmt(cell?.estimateActualQtyTillDate), _kCellW, isOverrun: overrun),
              _cell(_fmt(cell?.actualQty), _kCellW, isOverrun: overrun),
            ];
          }),
        ],
      ),
    );
  }

  Widget _label(String text, double width, {bool grey = false}) => Container(
        width: width,
        height: _kRowH,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
            border: Border(right: BorderSide(color: Colors.grey.shade200))),
        alignment: Alignment.centerLeft,
        child: Text(text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12,
                color: grey ? Colors.grey.shade500 : Colors.black87)),
      );

  Widget _cell(String text, double width, {required bool isOverrun}) {
    return Container(
      width: width,
      height: _kRowH,
      decoration: BoxDecoration(
        color: isOverrun ? const Color(0xFFFFC7CE).withValues(alpha: 0.5) : null,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200),
          left: isOverrun
              ? const BorderSide(color: Color(0xFFD32F2F), width: 1.5)
              : BorderSide.none,
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isOverrun ? const Color(0xFF9C0006) : Colors.black87,
          fontWeight: isOverrun ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}
