class OutputFile {
  final String fileId;
  final String filename;
  final String downloadUrl;
  final int sizeBytes;
  final String reportLabel;

  const OutputFile({
    required this.fileId,
    required this.filename,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.reportLabel,
  });

  factory OutputFile.fromJson(Map<String, dynamic> json) {
    return OutputFile(
      fileId: json['file_id'] as String,
      filename: json['filename'] as String,
      downloadUrl: json['download_url'] as String,
      sizeBytes: json['size_bytes'] as int,
      reportLabel: json['report_label'] as String,
    );
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class GenerateReportResult {
  final String jobId;
  final String status;
  final List<OutputFile> outputFiles;

  const GenerateReportResult({
    required this.jobId,
    required this.status,
    required this.outputFiles,
  });

  factory GenerateReportResult.fromJson(Map<String, dynamic> json) {
    return GenerateReportResult(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
      outputFiles: (json['output_files'] as List)
          .map((e) => OutputFile.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
