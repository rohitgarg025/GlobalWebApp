import 'package:flutter/material.dart';

import '../models/report_type.dart';
import '../services/api_service.dart';
import 'step2_file_select_screen.dart';

class Step1ReportTypeScreen extends StatefulWidget {
  const Step1ReportTypeScreen({super.key});

  @override
  State<Step1ReportTypeScreen> createState() => _Step1ReportTypeScreenState();
}

class _Step1ReportTypeScreenState extends State<Step1ReportTypeScreen> {
  final _api = ApiService();
  List<ReportType> _reportTypes = [];
  ReportType? _selected;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReportTypes();
  }

  Future<void> _loadReportTypes() async {
    try {
      final types = await _api.fetchReportTypes();
      setState(() {
        _reportTypes = types;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Cannot connect to backend.\nMake sure the server is running on port 8765.\n\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    _buildStepIndicator(1),
                    const SizedBox(height: 28),
                    Text(
                      'Select Report Type',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose the type of Excel report you want to generate.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    _buildBody(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF0066CC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.assessment, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Global Buildestate',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0066CC)),
            ),
            Text('Report Transformer', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
      ],
    );
  }

  Widget _buildStepIndicator(int current) {
    return Row(
      children: List.generate(3, (i) {
        final step = i + 1;
        final active = step == current;
        final done = step < current;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: done ? Colors.green : (active ? const Color(0xFF0066CC) : Colors.grey[300]),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text('$step',
                          style: TextStyle(
                            color: active ? Colors.white : Colors.grey[600],
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          )),
                ),
              ),
              if (i < 2)
                Expanded(
                  child: Container(
                    height: 2,
                    color: done ? Colors.green : Colors.grey[300],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() { _loading = true; _error = null; });
              _loadReportTypes();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._reportTypes.map((type) => _ReportTypeCard(
          type: type,
          selected: _selected?.id == type.id,
          onTap: () => setState(() => _selected = type),
        )),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Step2FileSelectScreen(reportType: _selected!),
                    ),
                  ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0066CC),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportTypeCard extends StatelessWidget {
  final ReportType type;
  final bool selected;
  final VoidCallback onTap;

  const _ReportTypeCard({required this.type, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F0FE) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF0066CC) : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? const Color(0xFF0066CC) : Colors.grey[400]!,
                  width: 2,
                ),
                color: selected ? const Color(0xFF0066CC) : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 12)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: selected ? const Color(0xFF0066CC) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    type.description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
