part of 'project_schedule_screen.dart';

// ─── Gantt painters ───────────────────────────────────────────────────────────

class _GanttHeaderPainter extends CustomPainter {
  final DateTime minDate;
  final int totalDays;

  const _GanttHeaderPainter({required this.minDate, required this.totalDays});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.grey.shade50;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final linePaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    const textStyle = TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600);

    DateTime cursor = DateTime(minDate.year, minDate.month, 1);
    final endDate = minDate.add(Duration(days: totalDays));

    while (cursor.isBefore(endDate)) {
      final x = (cursor.difference(minDate).inDays * size.width) / totalDays;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

      final tp = TextPainter(
        text: TextSpan(text: _monthLabel(cursor), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(math.max(x, 0) + 6, (size.height - tp.height) / 2));

      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    canvas.drawLine(
        Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), linePaint);
  }

  String _monthLabel(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.year}';
  }

  @override
  bool shouldRepaint(_GanttHeaderPainter old) =>
      old.minDate != minDate || old.totalDays != totalDays;
}

class _GanttBodyPainter extends CustomPainter {
  final List<_Row> rows;
  final DateTime minDate;
  final int totalDays;
  final double rowHeight;

  const _GanttBodyPainter({
    required this.rows,
    required this.minDate,
    required this.totalDays,
    required this.rowHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgEven = Paint()..color = Colors.white;
    final bgOdd = Paint()..color = const Color(0xFFFAFAFB);
    final linePaint = Paint()
      ..color = Colors.grey.shade100
      ..strokeWidth = 1;
    final monthLinePaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;
    final barPaint = Paint()..color = _kBrand;
    final groupPaint = Paint()..color = _kGroup;

    // Row backgrounds (one extra for the table's new-entry row)
    final slots = (size.height / rowHeight).ceil();
    for (int i = 0; i < slots; i++) {
      final y = i * rowHeight;
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, rowHeight), i.isEven ? bgEven : bgOdd);
      canvas.drawLine(Offset(0, y + rowHeight), Offset(size.width, y + rowHeight), linePaint);
    }

    DateTime cursor = DateTime(minDate.year, minDate.month, 1);
    final endDate = minDate.add(Duration(days: totalDays));
    while (cursor.isBefore(endDate)) {
      final x = (cursor.difference(minDate).inDays * size.width) / totalDays;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), monthLinePaint);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final a = row.activity;
      // Empty groups carry placeholder dates; don't draw them.
      if (!row.hasDates) continue;
      final start = DateTime.tryParse(a.startDate);
      final finish = DateTime.tryParse(a.finishDate);
      if (start == null || finish == null) continue;

      final x1 = (start.difference(minDate).inDays * size.width) / totalDays;
      final x2 = ((finish.difference(minDate).inDays + 1) * size.width) / totalDays;
      if (x2 <= x1) continue;
      final y = i * rowHeight;

      if (a.isGroup) {
        // MS Project–style summary bar: thin bar with downward end tabs.
        final barY = y + rowHeight / 2 - 5;
        canvas.drawRect(Rect.fromLTWH(x1, barY, x2 - x1, 6), groupPaint);
        for (final ex in [x1, x2]) {
          final dir = ex == x1 ? 1.0 : -1.0;
          final path = Path()
            ..moveTo(ex, barY)
            ..lineTo(ex + dir * 6, barY)
            ..lineTo(ex, barY + 12)
            ..close();
          canvas.drawPath(path, groupPaint);
        }
        continue;
      }

      final barH = rowHeight - 16;
      final barY = y + 8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x1, barY, x2 - x1, barH),
          const Radius.circular(3),
        ),
        barPaint,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: a.code,
          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width <= x2 - x1 - 8) {
        tp.paint(canvas, Offset(x1 + 4, barY + (barH - tp.height) / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_GanttBodyPainter old) => true;
}
