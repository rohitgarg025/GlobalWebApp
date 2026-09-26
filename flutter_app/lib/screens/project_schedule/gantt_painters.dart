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

/// Horizontal extent of a row's bar, or null when it has nothing to draw.
(double, double)? _barX(_Row row, DateTime minDate, int totalDays, double width) {
  if (!row.hasDates) return null; // empty groups only hold placeholder dates
  final start = DateTime.tryParse(row.activity.startDate);
  final finish = DateTime.tryParse(row.activity.finishDate);
  if (start == null || finish == null) return null;
  final x1 = (start.difference(minDate).inDays * width) / totalDays;
  final x2 = ((finish.difference(minDate).inDays + 1) * width) / totalDays;
  return x2 > x1 ? (x1, x2) : null;
}

class _GanttBodyPainter extends CustomPainter {
  /// One entry per table line; null marks an inline entry row (no bar).
  final List<_Row?> rows;
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
      if (row == null) continue;
      final a = row.activity;
      final span = _barX(row, minDate, totalDays, size.width);
      if (span == null) continue;
      final (x1, x2) = span;
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
          text: a.name,
          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      );
      // Names are long; truncate to the bar rather than hiding the label.
      final room = x2 - x1 - 8;
      if (room >= 18) {
        tp.layout(maxWidth: room);
        tp.paint(canvas, Offset(x1 + 4, barY + (barH - tp.height) / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_GanttBodyPainter old) => true;
}

// ─── Gantt body with hover details ────────────────────────────────────────────

class _GanttBody extends StatefulWidget {
  final List<_Row?> rows;
  final DateTime minDate;
  final int totalDays;
  final double width;
  final double height;

  /// Label/value lines for the hover card.
  final List<(String, String)> Function(_Row row) details;

  const _GanttBody({
    required this.rows,
    required this.minDate,
    required this.totalDays,
    required this.width,
    required this.height,
    required this.details,
  });

  @override
  State<_GanttBody> createState() => _GanttBodyState();
}

class _GanttBodyState extends State<_GanttBody> {
  final _portal = OverlayPortalController();
  _Row? _hovered;
  Offset _pointer = Offset.zero;

  _Row? _hitTest(Offset local) {
    final i = local.dy ~/ _kRowH;
    if (i < 0 || i >= widget.rows.length) return null;
    final row = widget.rows[i];
    if (row == null) return null;
    final span = _barX(row, widget.minDate, widget.totalDays, widget.width);
    if (span == null) return null;
    // A few px of slack makes 1-day bars easy to hit.
    return local.dx >= span.$1 - 3 && local.dx <= span.$2 + 3 ? row : null;
  }

  void _onHover(PointerHoverEvent e) {
    final hit = _hitTest(e.localPosition);
    if (hit == null) {
      if (_hovered != null) {
        _portal.hide();
        setState(() => _hovered = null);
      }
      return;
    }
    setState(() {
      _hovered = hit;
      _pointer = e.position;
    });
    _portal.show();
  }

  void _onExit(PointerExitEvent _) {
    _portal.hide();
    if (_hovered != null) setState(() => _hovered = null);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (ctx) {
        final row = _hovered;
        if (row == null) return const SizedBox.shrink();
        const cardW = 260.0;
        final screen = MediaQuery.sizeOf(ctx);
        final lines = widget.details(row);
        final estH = 44.0 + lines.length * 19;
        var left = _pointer.dx + 14;
        if (left + cardW > screen.width - 8) left = _pointer.dx - cardW - 14;
        var top = _pointer.dy + 14;
        if (top + estH > screen.height - 8) top = _pointer.dy - estH - 8;
        return Positioned(
          left: math.max(8, left),
          top: math.max(8, top),
          child: IgnorePointer(child: _BarDetailsCard(row: row, lines: lines, width: cardW)),
        );
      },
      child: MouseRegion(
        onHover: _onHover,
        onExit: _onExit,
        cursor: _hovered != null ? SystemMouseCursors.help : MouseCursor.defer,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: CustomPaint(
            painter: _GanttBodyPainter(
              rows: widget.rows,
              minDate: widget.minDate,
              totalDays: widget.totalDays,
              rowHeight: _kRowH,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarDetailsCard extends StatelessWidget {
  final _Row row;
  final List<(String, String)> lines;
  final double width;

  const _BarDetailsCard({required this.row, required this.lines, required this.width});

  @override
  Widget build(BuildContext context) {
    final a = row.activity;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: a.isGroup ? _kGroup : _kBrand, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _TypeChip(isGroup: a.isGroup),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(a.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final (label, value) in lines)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 86,
                      child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ),
                    Expanded(
                      child: Text(value,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
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
