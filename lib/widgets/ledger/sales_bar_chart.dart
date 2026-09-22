import 'package:flutter/material.dart';

import '../../models/ledger.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// Daily bars for the dashboard: sales stacked (shop on top of app) with a
/// thin outgoing bar beside each day. Drawn by hand — a dependency-free
/// painter is plenty for 31 bars, and it stays in the app's own colours.
class SalesBarChart extends StatelessWidget {
  final List<DailyPoint> points;
  final DateTime start;
  final DateTime end;

  const SalesBarChart({
    super.key,
    required this.points,
    required this.start,
    required this.end,
  });

  @override
  Widget build(BuildContext context) {
    // Fill every day in the window so gaps read as zero, not as missing.
    final byDay = {for (final p in points) _key(p.day): p};
    final days = <DailyPoint>[];
    var d = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (d.isBefore(last)) {
      days.add(byDay[_key(d)] ?? DailyPoint(day: d, local: 0, app: 0, out: 0));
      d = d.add(const Duration(days: 1));
      if (days.length > 62) break; // custom ranges: cap what we draw
    }
    final maxValue = days.fold<double>(0, (m, p) => [m, p.sales, p.out].reduce((a, b) => a > b ? a : b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            _Legend(color: AppColors.primary, label: 'المحل'),
            SizedBox(width: 12),
            _Legend(color: AppColors.tertiaryContainer, label: 'التطبيق'),
            SizedBox(width: 12),
            _Legend(color: AppColors.error, label: 'مصاريف ومشتريات'),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          width: double.infinity,
          child: maxValue == 0
              ? const Center(
                  child: Text('لا حركة في هذه الفترة',
                      style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12.5)),
                )
              : CustomPaint(painter: _BarsPainter(days, maxValue)),
        ),
        const SizedBox(height: 4),
        if (days.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_short(days.last.day), style: _axis),
              if (days.length > 2) Text(_short(days[days.length ~/ 2].day), style: _axis),
              Text(_short(days.first.day), style: _axis),
            ],
          ),
      ],
    );
  }

  static const _axis = TextStyle(fontSize: 10.5, color: AppColors.onSurfaceVariant);
  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
  static String _short(DateTime d) => '${d.day}/${d.month}';
}

class _BarsPainter extends CustomPainter {
  final List<DailyPoint> days;
  final double maxValue;
  _BarsPainter(this.days, this.maxValue);

  @override
  void paint(Canvas canvas, Size size) {
    final n = days.length;
    if (n == 0) return;
    final slot = size.width / n;
    final gap = slot * 0.22;
    final salesW = (slot - gap) * 0.68;
    final outW = (slot - gap) * 0.32;
    final scale = (size.height - 14) / maxValue;

    final grid = Paint()
      ..color = AppColors.surfaceContainerHigh
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height - (size.height - 14) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final local = Paint()..color = AppColors.primary;
    final app = Paint()..color = AppColors.tertiaryContainer;
    final out = Paint()..color = AppColors.error.withValues(alpha: 0.75);

    for (var i = 0; i < n; i++) {
      // RTL: the first day sits at the right edge.
      final x0 = size.width - (i + 1) * slot + gap / 2;
      final p = days[i];
      final bottom = size.height;

      final appH = p.app * scale;
      final localH = p.local * scale;
      if (appH > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x0 + outW, bottom - appH, salesW, appH), const Radius.circular(2)),
          app,
        );
      }
      if (localH > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x0 + outW, bottom - appH - localH, salesW, localH),
            const Radius.circular(2)),
          local,
        );
      }
      final outH = p.out * scale;
      if (outH > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x0, bottom - outH, outW - 1, outH), const Radius.circular(2)),
          out,
        );
      }
    }

    // Top-of-scale label so the reader has a number to anchor on.
    final tp = TextPainter(
      text: TextSpan(text: formatNum(maxValue), style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(0, 0));
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.days != days || old.maxValue != maxValue;
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}
