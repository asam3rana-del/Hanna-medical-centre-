import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/whatsapp_sender.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_plan_math.dart';
import 'inst_plan_repository.dart';
import 'inst_plans_screen.dart';
import 'inst_ui.dart';

/// Kis ko yaad-dahani (Step 22, PURE — test/installment_bulk_remind_test.dart).
/// [days] = 0: aaj ki + late; 1: kal tak; 3: 3 din tak. Sirf chalte plan, phone wale; late pehle, phir tareekh.
List<PlanView> remindTargets(List<PlanView> plans, {required int today, int days = 0}) {
  final until = DateTime.fromMillisecondsSinceEpoch(today).add(Duration(days: days)).millisecondsSinceEpoch;
  final out = plans.where((v) {
    if (!v.plan.isActive || v.customerPhone.trim().isEmpty) return false;
    if (v.status.dueNow > 0.5) return true;
    final n = v.status.next;
    return n != null && n.dueDate <= until;
  }).toList();
  out.sort((a, b) {
    final late = b.status.daysLate.compareTo(a.status.daysLate);
    if (late != 0) return late;
    return (a.status.next?.dueDate ?? 0).compareTo(b.status.next?.dueDate ?? 0);
  });
  return out;
}

/// Ek tap mein sab ko WhatsApp yaad-dahani: "Agla bhejo" har dafa agle customer ki chat kholta hai (message tayyar),
/// aap sirf Send dabate hain. Aaj kis ko bhej diya — yaad rehta hai (isi device par, aaj ke din).
class InstBulkRemindScreen extends StatefulWidget {
  const InstBulkRemindScreen({super.key});

  @override
  State<InstBulkRemindScreen> createState() => _InstBulkRemindScreenState();
}

class _InstBulkRemindScreenState extends State<InstBulkRemindScreen> {
  List<PlanView> _all = const [];
  Set<int> _sent = {};
  int _days = 0;
  bool _loaded = false;

  String get _key {
    final d = DateTime.now();
    return 'inst_reminded_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await InstPlanRepository.instance.list();
    var sent = <int>{};
    try {
      final sp = await SharedPreferences.getInstance();
      sent = (sp.getStringList(_key) ?? const []).map(int.tryParse).whereType<int>().toSet();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _all = all;
      _sent = sent;
      _loaded = true;
    });
  }

  Future<void> _mark(int planId) async {
    setState(() => _sent.add(planId));
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_key, _sent.map((e) => '$e').toList());
    } catch (_) {}
  }

  Future<void> _send(PlanView v) async {
    final shop = await loadShopHeader();
    if (!mounted) return;
    await sendOnWhatsApp(context, phone: v.customerPhone, text: planReminderText(v, shop));
    await _mark(v.plan.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final list = remindTargets(_all, today: dayStart(DateTime.now()), days: _days);
    final left = list.where((v) => !_sent.contains(v.plan.id)).toList();
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Send reminders', 'یاد دہانی بھیجیں'),
            Loc.t('${list.length} customers • ${left.length} left', '${list.length} کسٹمر • ${left.length} باقی')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(spacing: 8, children: [
            for (final (d, label) in [
              (0, Loc.t('Today + late', 'آج + لیٹ')),
              (1, Loc.t('Till tomorrow', 'کل تک')),
              (3, Loc.t('Next 3 days', 'اگلے 3 دن')),
            ])
              ChoiceChip(label: Text(label), selected: _days == d, onSelected: (_) => setState(() => _days = d)),
          ]),
        ),
        if (_loaded && left.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.teal, minimumSize: const Size.fromHeight(54)),
              onPressed: () => _send(left.first),
              icon: const Icon(Icons.send),
              label: Text(Loc.t('Send next: ${left.first.customerName}', 'اگلا بھیجیں: ${left.first.customerName}'),
                  style: const TextStyle(fontSize: 16)),
            ),
          ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? Center(child: Text(Loc.t('Nobody to remind.', 'کسی کو یاد دہانی کی ضرورت نہیں۔'), style: TextStyle(color: p.textMuted)))
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
                      for (final v in list) _row(p, v),
                    ]),
        ),
      ]),
    );
  }

  Widget _row(AppPalette p, PlanView v) {
    final st = v.status;
    final sent = _sent.contains(v.plan.id);
    final amount = st.dueNow > 0.5 ? st.dueNow : (st.next?.remaining ?? 0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: instCard(p),
      child: ListTile(
        title: Text(v.customerName, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
        subtitle: Text(
          [
            instRs(amount),
            if (st.daysLate > 0) Loc.t('${st.daysLate} days late', '${st.daysLate} دن لیٹ'),
            v.customerPhone,
          ].join('  •  '),
          style: TextStyle(color: st.daysLate > 0 ? p.red : p.textMuted, fontSize: 12),
        ),
        trailing: sent
            ? TextButton.icon(
                onPressed: () => _send(v),
                icon: Icon(Icons.check_circle, color: p.teal),
                label: Text(Loc.t('Sent', 'بھیج دیا'), style: TextStyle(color: p.teal)),
              )
            : IconButton(
                tooltip: Loc.t('Send', 'بھیجیں'),
                icon: Icon(Icons.send, color: p.navy),
                onPressed: () => _send(v),
              ),
      ),
    );
  }
}
