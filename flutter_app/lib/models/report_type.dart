class ReportType {
  final String id;
  final String displayName;
  final String description;
  final int requiredFilesCount;
  final List<String> inputFileLabels;
  final bool supportsMultipleProjects;
  final int? filesPerProject;

  const ReportType({
    required this.id,
    required this.displayName,
    required this.description,
    required this.requiredFilesCount,
    required this.inputFileLabels,
    this.supportsMultipleProjects = false,
    this.filesPerProject,
  });

  factory ReportType.fromJson(Map<String, dynamic> json) {
    return ReportType(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      description: json['description'] as String,
      requiredFilesCount: json['required_files_count'] as int,
      inputFileLabels: List<String>.from(json['input_file_labels']),
      supportsMultipleProjects: json['supports_multiple_projects'] as bool? ?? false,
      filesPerProject: json['files_per_project'] as int?,
    );
  }
}
