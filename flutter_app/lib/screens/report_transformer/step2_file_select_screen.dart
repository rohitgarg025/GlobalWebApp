import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/report_type.dart';
import '../../services/api_service.dart';
import 'step3_output_screen.dart';

class Step2FileSelectScreen extends StatefulWidget {
  final ReportType reportType;
  const Step2FileSelectScreen({super.key, required this.reportType});

  @override
  State<Step2FileSelectScreen> createState() => _Step2FileSelectScreenState();
}

class _Step2FileSelectScreenState extends State<Step2FileSelectScreen> {
  final _api = ApiService();
  bool _generating = false;
  String? _error;

  // ── Fixed-count mode (requiredFilesCount > 0) ──────────────────────────────
  // One nullable slot per required file, order is guaranteed.
  late List<PlatformFile?> _slotFiles;

  // ── Multi-project mode (requiredFilesCount == -1) ─────────────────────────
  // Each "set" is a list of 3 nullable slots.
  final List<List<PlatformFile?>> _projectSets = [];

  bool get _isMultiProject => widget.reportType.requiredFilesCount == -1;
  int get _filesPerSet => widget.reportType.filesPerProject ?? 3;

  @override
  void initState() {
    super.initState();
    if (!_isMultiProject) {
      _slotFiles = List.filled(widget.reportType.requiredFilesCount, null);
    } else {
      _projectSets.add(List.filled(_filesPerSet, null));
    }
  }

  bool get _isValidFileCount {
    if (!_isMultiProject) {
      return _slotFiles.every((f) => f != null);
    } else {
      return _projectSets.isNotEmpty &&
          _projectSets.every((set) => set.every((f) => f != null));
    }
  }

  List<PlatformFile> get _orderedFiles {
    if (!_isMultiProject) {
      return _slotFiles.whereType<PlatformFile>().toList();
    } else {
      return _projectSets.expand((set) => set.whereType<PlatformFile>()).toList();
    }
  }

  Future<void> _pickFileForSlot(int slotIndex) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _slotFiles[slotIndex] = result.files.first;
        _error = null;
      });
    }
  }

  Future<void> _pickFileForProjectSlot(int setIndex, int slotIndex) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _projectSets[setIndex][slotIndex] = result.files.first;
        _error = null;
      });
    }
  }

  void _addProjectSet() {
    setState(() {
      _projectSets.add(List.filled(_filesPerSet, null));
    });
  }

  void _removeProjectSet(int setIndex) {
    setState(() {
      _projectSets.removeAt(setIndex);
    });
  }

  Future<void> _generate() async {
    if (!_isValidFileCount) return;

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final result = await _api.generateReport(
        reportTypeId: widget.reportType.id,
        files: _orderedFiles,
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
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.reportType.description,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    if (_isMultiProject)
                      _buildMultiProjectSlots()
                    else
                      _buildFixedSlots(),
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

  // ── Fixed-count slot UI ────────────────────────────────────────────────────

  Widget _buildFixedSlots() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoBanner(
          'Select each file in the correct order using the buttons below.',
        ),
        const SizedBox(height: 16),
        ...List.generate(
          widget.reportType.requiredFilesCount,
          (i) => _buildFileSlot(
            slotNumber: i + 1,
            label: i < widget.reportType.inputFileLabels.length
                ? widget.reportType.inputFileLabels[i]
                : 'File ${i + 1}',
            file: _slotFiles[i],
            onPick: () => _pickFileForSlot(i),
            onClear: () => setState(() => _slotFiles[i] = null),
          ),
        ),
      ],
    );
  }

  // ── Multi-project slot UI ──────────────────────────────────────────────────

  Widget _buildMultiProjectSlots() {
    final labels = widget.reportType.inputFileLabels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoBanner(
          'Add one set of files per project. '
          'Each set must contain ${_filesPerSet} files in order.',
        ),
        const SizedBox(height: 16),
        ...List.generate(_projectSets.length, (setIdx) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0066CC).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Project ${setIdx + 1}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0066CC),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_projectSets.length > 1)
                    TextButton.icon(
                      onPressed: () => _removeProjectSet(setIdx),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Remove', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ...List.generate(_filesPerSet, (slotIdx) {
                final label = slotIdx < labels.length
                    ? labels[slotIdx]
                    : 'File ${slotIdx + 1}';
                return _buildFileSlot(
                  slotNumber: slotIdx + 1,
                  label: label,
                  file: _projectSets[setIdx][slotIdx],
                  onPick: () => _pickFileForProjectSlot(setIdx, slotIdx),
                  onClear: () =>
                      setState(() => _projectSets[setIdx][slotIdx] = null),
                );
              }),
              if (setIdx < _projectSets.length - 1)
                const Divider(height: 32),
            ],
          );
        }),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addProjectSet,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Another Project'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0066CC),
            side: const BorderSide(color: Color(0xFF0066CC)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  // ── Shared file slot widget ────────────────────────────────────────────────

  Widget _buildFileSlot({
    required int slotNumber,
    required String label,
    required PlatformFile? file,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final filled = file != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: filled ? Colors.green.withValues(alpha: 0.04) : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: filled ? Colors.green.shade300 : Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Slot number badge
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: filled
                    ? Colors.green.withValues(alpha: 0.15)
                    : const Color(0xFF0066CC).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: filled
                    ? Icon(Icons.check, size: 14, color: Colors.green[700])
                    : Text(
                        '$slotNumber',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0066CC),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Label + filename
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: filled ? Colors.black87 : Colors.grey[700],
                    ),
                  ),
                  if (filled) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.description_outlined,
                            size: 13, color: Colors.green),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            file!.name,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatSize(file.size),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      'No file selected',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Action button
            if (filled)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: Colors.grey[500]),
                tooltip: 'Remove file',
                onPressed: onClear,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            else
              ElevatedButton(
                onPressed: onPick,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066CC),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                  elevation: 0,
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
                child: const Text('Browse'),
              ),
          ],
        ),
      ),
    );
  }

  // ── Supporting widgets ─────────────────────────────────────────────────────

  Widget _buildInfoBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF0066CC)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF0066CC),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
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
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0066CC)),
            ),
            Text('Report Transformer',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                  color: done
                      ? Colors.green
                      : (active ? const Color(0xFF0066CC) : Colors.grey[300]),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '$step',
                          style: TextStyle(
                            color: active ? Colors.white : Colors.grey[600],
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              if (i < 2)
                Expanded(
                  child: Container(
                      height: 2,
                      color: done ? Colors.green : Colors.grey[300]),
                ),
            ],
          ),
        );
      }),
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
          Expanded(
              child: Text(_error!,
                  style: TextStyle(color: Colors.red[700], fontSize: 13))),
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
            backgroundColor: Colors.grey[200],
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFF0066CC)),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('Generating report…',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          const SizedBox(height: 12),
        ],
        ElevatedButton(
          onPressed: (_isValidFileCount && !_generating) ? _generate : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0066CC),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _generating
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, size: 20),
                    SizedBox(width: 8),
                    Text('Generate Report',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
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
