class Project {
  final int id;
  final String name;
  final String? code;
  final String? location;
  final String? clientName;
  final String status;
  final String? createdAt;
  final String? createdBy;

  const Project({
    required this.id,
    required this.name,
    this.code,
    this.location,
    this.clientName,
    this.status = 'active',
    this.createdAt,
    this.createdBy,
  });

  bool get isActive => status == 'active';

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as int,
        name: j['name'] as String,
        code: j['code'] as String?,
        location: j['location'] as String?,
        clientName: j['client_name'] as String?,
        status: (j['status'] as String?) ?? 'active',
        createdAt: j['created_at'] as String?,
        createdBy: j['created_by'] as String?,
      );
}
