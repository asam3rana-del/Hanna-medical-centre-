import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_plan_repository.dart';
import 'inst_repository.dart';
import 'inst_ui.dart';

/// Chhota label: 1250000 -> 12.5L, 85000 -> 85K.
String shortRs(double v) {
  final a = v.abs();
  final s = v < 0 ? '-' : '';
  if (a >= 10000000) return '$s${(a / 10000000).toStringAsFixed(a >= 100000000 ? 0 : 1)}Cr';
  if (a >= 100000) return '$s${(a / 100000).toStringAsFixed(a >= 1000000 ? 0 : 1)}L';
  if (a >= 1000) return '$s${(a / 1000).round()}K';
  return '$s${a.round()}';
}

/// Dashboard (Admin / Manager): pichhle 6 mahine ki sale, wasooli, munafa — bar chart (Step 26). Bina package.
class InstTrendChart extends StatefulWidget {
  const InstTrendChart({super.key});

  @override
  State<InstTrendChart> createState() => _InstTrendChartState();
}

class _InstTrendChartState extends State<InstTrendChart> {
  List<MonthPoint>? _pts;
  int? _sel;

  @override
  void initState() {
    super.initState();
    InstRepository.instance.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    InstRepository.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pts = await InstPlanRepository.instance.monthlyTrend();
      if (mounted) setState(() => _pts = pts);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final pts = _pts;
    if (pts == null || pts.isEmpty) return const SizedBox.shrink();
    final maxV = pts.fold<double>(1, (m, x) => math.max(m, math.max(x.sale, math.max(x.collected, x.profit))));
    final sel = _sel ?? pts.length - 1;
    final cur = pts[sel];
    final colors = [p.navy, p.teal, p.amber];
    Widget legend(Color c, String t, double v) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text('$t ${instRs(v)}', style: TextStyle(color: p.textDark, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: instCard(p),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${Loc.t('Last 6 months', 'پچھلے 6 مہینے')} — ${DateFormat('MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(cur.monthStart))}',
            style: TextStyle(color: p.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 4, children: [
          legend(colors[0], Loc.t('Sale', 'سیل'), cur.sale),
          legend(colors[1], Loc.t('Collected', 'وصولی'), cur.collected),
          legend(colors[2], Loc.t('Profit', 'منافع'), cur.profit),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < pts.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _sel = i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: i == sel ? p.navy.withOpacity(0.06) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Expanded(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (final (j, v) in [(0, pts[i].sale), (1, pts[i].collected), (2, pts[i].profit)])
                            Flexible(
                              child: FractionallySizedBox(
                                heightFactor: v <= 0 ? 0.01 : math.max(0.02, v / maxV),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: colors[j],
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      Text(DateFormat('MMM').format(DateTime.fromMillisecondsSinceEpoch(pts[i].monthStart)),
                          style: TextStyle(color: i == sel ? p.textDark : p.textMuted, fontSize: 10.5, fontWeight: FontWeight.w600)),
                      Text(shortRs(pts[i].sale), style: TextStyle(color: p.textMuted, fontSize: 9.5)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
