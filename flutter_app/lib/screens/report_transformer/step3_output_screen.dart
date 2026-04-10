import 'package:flutter/material.dart';

import '../../models/output_file.dart';
import '../../services/api_service.dart';
import '../../services/download_service.dart';
import 'step1_report_type_screen.dart';

class Step3OutputScreen extends StatefulWidget {
  final GenerateReportResult result;
  final ApiService api;

  const Step3OutputScreen({super.key, required this.result, required this.api});

  @override
  State<Step3OutputScreen> createState() => _Step3OutputScreenState();
}

class _Step3OutputScreenState extends State<Step3OutputScreen> {
  final Set<String> _downloading = {};
  final Set<String> _downloaded = {};

  Future<void> _download(OutputFile file) async {
    setState(() => _downloading.add(file.fileId));
    try {
      final bytes = await widget.api.downloadFile(file.fileId);
      downloadFileOnWeb(bytes, file.filename);
      setState(() => _downloaded.add(file.fileId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      setState(() => _downloading.remove(file.fileId));
    }
  }

  Future<void> _downloadAll() async {
    for (final file in widget.result.outputFiles) {
      if (!_downloaded.contains(file.fileId)) {
        await _download(file);
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
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
                  _buildStepIndicator(3),
                  const SizedBox(height: 28),
                  _buildSuccessBanner(),
                  const SizedBox(height: 24),
                  Text(
                    '${widget.result.outputFiles.length} Report${widget.result.outputFiles.length > 1 ? 's' : ''} Generated',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  ...widget.result.outputFiles.map((f) => _FileDownloadTile(
                    file: f,
                    isDownloading: _downloading.contains(f.fileId),
                    isDownloaded: _downloaded.contains(f.fileId),
                    onDownload: () => _download(f),
                  )),
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
        final done = step <= current;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: done ? Colors.green : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text('$step',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.bold)),
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

  Widget _buildSuccessBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.green[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle, color: Colors.green[700], size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reports generated successfully!',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[800])),
                Text('Click Download to save each report.',
                    style: TextStyle(fontSize: 12, color: Colors.green[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final allDownloaded = widget.result.outputFiles.every((f) => _downloaded.contains(f.fileId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.result.outputFiles.length > 1)
          OutlinedButton.icon(
            onPressed: allDownloaded || _downloading.isNotEmpty ? null : _downloadAll,
            icon: const Icon(Icons.download_for_offline),
            label: const Text('Download All'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Color(0xFF0066CC)),
              foregroundColor: const Color(0xFF0066CC),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const Step1ReportTypeScreen()),
            (_) => false,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0066CC),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Generate Another Report',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _FileDownloadTile extends StatelessWidget {
  final OutputFile file;
  final bool isDownloading;
  final bool isDownloaded;
  final VoidCallback onDownload;

  const _FileDownloadTile({
    required this.file,
    required this.isDownloading,
    required this.isDownloaded,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDownloaded ? Colors.green[50] : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDownloaded ? Colors.green[200]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF0066CC).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.table_chart, color: Color(0xFF0066CC), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.reportLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${file.filename}  •  ${file.formattedSize}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildDownloadButton(),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    if (isDownloading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0066CC)),
      );
    }
    if (isDownloaded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green[100],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 14, color: Colors.green[700]),
            const SizedBox(width: 4),
            Text('Saved', style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onDownload,
      icon: const Icon(Icons.download, size: 16),
      label: const Text('Download', style: TextStyle(fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }
}
