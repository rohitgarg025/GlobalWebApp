import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dotted_border/dotted_border.dart';

import '../models/report_type.dart';
import '../services/api_service.dart';
import 'step3_output_screen.dart';

class Step2FileSelectScreen extends StatefulWidget {
  final ReportType reportType;
  const Step2FileSelectScreen({super.key, required this.reportType});

  @override
  State<Step2FileSelectScreen> createState() => _Step2FileSelectScreenState();
}

class _Step2FileSelectScreenState extends State<Step2FileSelectScreen> {
  final _api = ApiService();
  List<PlatformFile> _selectedFiles = [];
  bool _generating = false;
  double? _uploadProgress;
  String? _error;

  bool get _isValidFileCount {
    final required = widget.reportType.requiredFilesCount;
    if (required == -1) return _selectedFiles.isNotEmpty && _selectedFiles.length % 3 == 0;
    return _selectedFiles.length == required;
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      allowMultiple: true,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFiles = result.files;
        _error = null;
      });
    }
  }

  Future<void> _generate() async {
    if (!_isValidFileCount) return;

    setState(() {
      _generating = true;
      _error = null;
      _uploadProgress = null;
    });

    try {
      final result = await _api.generateReport(
        reportTypeId: widget.reportType.id,
        files: _selectedFiles,
      );
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Step3OutputScreen(result: result, api: _api),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0066CC)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
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
                  _buildStepIndicator(2),
                  const SizedBox(height: 28),
                  Text(
                    'Select Input Files',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.reportType.description,
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  _buildRequiredFilesHint(),
                  const SizedBox(height: 20),
                  _buildDropZone(),
                  if (_selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildFileList(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildError(),
                  ],
                  const SizedBox(height: 28),
                  _buildActions(),
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
                  child: Container(height: 2, color: done ? Colors.green : Colors.grey[300]),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildRequiredFilesHint() {
    final required = widget.reportType.requiredFilesCount;
    final labels = widget.reportType.inputFileLabels;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFF0066CC)),
              const SizedBox(width: 6),
              Text(
                required == -1
                    ? 'Upload files in multiples of 3 (one set per project)'
                    : 'Upload exactly $required file${required > 1 ? 's' : ''} in this order:',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0066CC)),
              ),
            ],
          ),
          if (required != -1) ...[
            const SizedBox(height: 6),
            ...labels.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 2, left: 22),
                  child: Text('${e.key + 1}. ${e.value}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF0066CC))),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildDropZone() {
    return GestureDetector(
      onTap: _pickFiles,
      child: DottedBorder(
        options: const RoundedRectDottedBorderOptions(
          color: Color(0xFF0066CC),
          strokeWidth: 2,
          dashPattern: [8, 4],
          radius: Radius.circular(12),
          padding: EdgeInsets.zero,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              Icon(Icons.upload_file, size: 40, color: Colors.grey[400]),
              const SizedBox(height: 12),
              const Text(
                'Click to browse Excel files',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                '.xlsx and .xls supported',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_selectedFiles.length} file${_selectedFiles.length > 1 ? 's' : ''} selected',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            TextButton(
              onPressed: () => setState(() => _selectedFiles = []),
              child: const Text('Clear all', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._selectedFiles.asMap().entries.map(
          (e) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066CC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      '${e.key + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0066CC),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.description_outlined, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.value.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatSize(e.value.size),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
        if (!_isValidFileCount && _selectedFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.reportType.requiredFilesCount == -1
                  ? 'File count must be a multiple of 3 (currently ${_selectedFiles.length})'
                  : 'Need exactly ${widget.reportType.requiredFilesCount} file(s), have ${_selectedFiles.length}',
              style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            ),
          ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red[700], size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_generating) ...[
          LinearProgressIndicator(
            value: _uploadProgress,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0066CC)),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('Generating report...', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          const SizedBox(height: 12),
        ],
        ElevatedButton(
          onPressed: (_isValidFileCount && !_generating) ? _generate : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0066CC),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _generating
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, size: 20),
                    SizedBox(width: 8),
                    Text('Generate Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
