class QsProject {
  final int id;
  final String name;
  final String createdAt;

  const QsProject({required this.id, required this.name, required this.createdAt});

  factory QsProject.fromJson(Map<String, dynamic> j) =>
      QsProject(id: j['id'], name: j['name'], createdAt: j['created_at'] ?? '');
}

class QsActivity {
  final int id;
  final String name;
  final String unit;

  const QsActivity({required this.id, required this.name, required this.unit});

  factory QsActivity.fromJson(Map<String, dynamic> j) =>
      QsActivity(id: j['id'], name: j['name'], unit: j['unit']);
}

class QsFloor {
  final int id;
  final int projectId;
  final String name;
  final int displayOrder;

  const QsFloor({
    required this.id,
    required this.projectId,
    required this.name,
    required this.displayOrder,
  });

  factory QsFloor.fromJson(Map<String, dynamic> j) => QsFloor(
        id: j['id'],
        projectId: j['project_id'],
        name: j['name'],
        displayOrder: j['display_order'] ?? 0,
      );
}

class QsCell {
  final int activityId;
  final int floorId;
  final double? totalEstimatedQty;
  final bool baselineLocked;
  final double? estimateActualQtyTillDate;
  final double? actualQty;
  final String? justification;

  const QsCell({
    required this.activityId,
    required this.floorId,
    this.totalEstimatedQty,
    required this.baselineLocked,
    this.estimateActualQtyTillDate,
    this.actualQty,
    this.justification,
  });

  bool get isOverrun =>
      actualQty != null &&
      totalEstimatedQty != null &&
      actualQty! > totalEstimatedQty!;

  factory QsCell.fromJson(Map<String, dynamic> j) => QsCell(
        activityId: j['activity_id'],
        floorId: j['floor_id'],
        totalEstimatedQty: (j['total_estimated_qty'] as num?)?.toDouble(),
        baselineLocked: j['baseline_locked'] ?? false,
        estimateActualQtyTillDate:
            (j['estimate_actual_qty_till_date'] as num?)?.toDouble(),
        actualQty: (j['actual_qty'] as num?)?.toDouble(),
        justification: j['justification'],
      );
}

class QsProjectData {
  final QsProject project;
  final String month;
  final List<QsFloor> floors;
  final List<QsActivity> activities;
  final List<QsCell> cells;

  const QsProjectData({
    required this.project,
    required this.month,
    required this.floors,
    required this.activities,
    required this.cells,
  });

  QsCell? cell(int activityId, int floorId) {
    try {
      return cells.firstWhere(
          (c) => c.activityId == activityId && c.floorId == floorId);
    } catch (_) {
      return null;
    }
  }

  factory QsProjectData.fromJson(Map<String, dynamic> j) => QsProjectData(
        project: QsProject.fromJson(j['project']),
        month: j['month'],
        floors: (j['floors'] as List).map((e) => QsFloor.fromJson(e)).toList(),
        activities:
            (j['activities'] as List).map((e) => QsActivity.fromJson(e)).toList(),
        cells: (j['cells'] as List).map((e) => QsCell.fromJson(e)).toList(),
      );
}

class QsOverrun {
  final int entryId;
  final String project;
  final String activity;
  final String unit;
  final String floor;
  final String month;
  final double totalEstimatedQty;
  final double actualQty;
  final double excess;
  final String? justification;

  const QsOverrun({
    required this.entryId,
    required this.project,
    required this.activity,
    required this.unit,
    required this.floor,
    required this.month,
    required this.totalEstimatedQty,
    required this.actualQty,
    required this.excess,
    this.justification,
  });

  factory QsOverrun.fromJson(Map<String, dynamic> j) => QsOverrun(
        entryId: j['entry_id'],
        project: j['project'],
        activity: j['activity'],
        unit: j['unit'],
        floor: j['floor'],
        month: j['month'],
        totalEstimatedQty: (j['total_estimated_qty'] as num).toDouble(),
        actualQty: (j['actual_qty'] as num).toDouble(),
        excess: (j['excess'] as num).toDouble(),
        justification: j['justification'],
      );
}
