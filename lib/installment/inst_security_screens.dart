import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_plan_repository.dart';
import 'inst_plans_screen.dart';
import 'inst_ui.dart';

String _d(int ms) => DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));

String securityKindLabel(String k) => switch (k) {
      securityCheque => Loc.t('Cheque', 'چیک'),
      securityStamp => Loc.t('Stamp paper', 'اسٹامپ پیپر'),
      _ => Loc.t('Other document', 'دوسرا کاغذ'),
    };

String securityTitle(InstSecurity s) => [
      securityKindLabel(s.kind),
      if (s.number.isNotEmpty) '#${s.number}',
      if (s.bank.isNotEmpty) s.bank,
    ].join('  •  ');

/// Plan detail ka hissa (Step 21): zamanat ke cheque / kaghzat — add, wapas diya, hatao.
class PlanSecuritiesSection extends StatefulWidget {
  final int planId;
  final bool planActive;
  const PlanSecuritiesSection({super.key, required this.planId, required this.planActive});

  @override
  State<PlanSecuritiesSection> createState() => _PlanSecuritiesSectionState();
}

class _PlanSecuritiesSectionState extends State<PlanSecuritiesSection> {
  List<InstSecurity> _list = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await InstPlanRepository.instance.securities(widget.planId);
    if (mounted) setState(() => _list = l);
  }

  Future<void> _add() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _AddSecurityDialog(planId: widget.planId));
    if (ok == true) await _load();
  }

  Future<void> _menu(InstSecurity s) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(s.returned ? Icons.undo : Icons.assignment_return_outlined),
            title: Text(s.returned
                ? Loc.t('Not returned (keep with shop)', 'واپس نہیں ہوا (دکان کے پاس)')
                : Loc.t('Returned to customer', 'کسٹمر کو واپس دے دیا')),
            onTap: () => Navigator.pop(ctx, 'ret'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(Loc.t('Delete (wrong entry)', 'حذف (غلط اندراج)')),
            onTap: () => Navigator.pop(ctx, 'del'),
          ),
        ]),
      ),
    );
    try {
      if (a == 'ret') await InstPlanRepository.instance.setSecurityReturned(s, !s.returned);
      if (a == 'del') await InstPlanRepository.instance.deleteSecurity(s);
      await _load();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final held = _list.where((s) => !s.returned).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      instSectionTitle(p, Loc.t('SECURITY (cheque / documents)', 'ضمانت (چیک / کاغذات)')),
      if (!widget.planActive && held > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Text(
              Loc.t('Plan is closed — return $held document(s) to the customer.', 'پلان بند ہے — $held کاغذ کسٹمر کو واپس کریں۔'),
              style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
        ),
      for (final s in _list)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: instCard(p),
          child: ListTile(
            onTap: () => _menu(s),
            leading: Icon(s.kind == securityCheque ? Icons.payments_outlined : Icons.description_outlined,
                color: s.returned ? p.textMuted : p.navy),
            title: Text(securityTitle(s),
                style: TextStyle(
                    color: s.returned ? p.textMuted : p.textDark,
                    fontWeight: FontWeight.bold,
                    decoration: s.returned ? TextDecoration.lineThrough : null)),
            subtitle: Text(
              [
                if (s.amount > 0) instRs(s.amount),
                if (s.note.isNotEmpty) s.note,
                s.returned ? '${Loc.t('Returned', 'واپس')} ${_d(s.returnedAt)}' : Loc.t('With shop', 'دکان کے پاس'),
              ].join('  •  '),
              style: TextStyle(color: s.returned ? p.teal : p.textMuted, fontSize: 12),
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(Loc.t('Add cheque / document', 'چیک / کاغذ شامل کریں')),
      ),
    ]);
  }
}

class _AddSecurityDialog extends StatefulWidget {
  final int planId;
  const _AddSecurityDialog({required this.planId});

  @override
  State<_AddSecurityDialog> createState() => _AddSecurityDialogState();
}

class _AddSecurityDialogState extends State<_AddSecurityDialog> {
  String _kind = securityCheque;
  final _no = TextEditingController();
  final _bank = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _no.dispose();
    _bank.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await InstPlanRepository.instance.addSecurity(widget.planId,
          kind: _kind, number: _no.text, bank: _bank.text, amount: instParse(_amount.text), note: _note.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        instToast(context, instErr(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cheque = _kind == securityCheque;
    return AlertDialog(
      title: Text(Loc.t('Security document', 'ضمانت کا کاغذ')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: _kind,
            isExpanded: true,
            items: [for (final k in securityKinds) DropdownMenuItem(value: k, child: Text(securityKindLabel(k)))],
            onChanged: (k) => setState(() => _kind = k ?? _kind),
          ),
          TextField(
            controller: _no,
            decoration: InputDecoration(labelText: cheque ? Loc.t('Cheque no.', 'چیک نمبر') : Loc.t('Number (optional)', 'نمبر (اختیاری)')),
          ),
          if (cheque) TextField(controller: _bank, decoration: InputDecoration(labelText: Loc.t('Bank', 'بینک'))),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(labelText: Loc.t('Amount (optional)', 'رقم (اختیاری)')),
          ),
          TextField(controller: _note, decoration: InputDecoration(labelText: Loc.t('Note (whose cheque, date...)', 'نوٹ (کس کا چیک، تاریخ...)'))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
        TextButton(onPressed: _saving ? null : _save, child: Text(Loc.t('Save', 'محفوظ کریں'))),
      ],
    );
  }
}

/// Dukaan ke paas pare sab cheque / kaghzat (Step 21). Upar woh jin ka plan band ho chuka (wapas karne hain).
class InstHeldSecuritiesScreen extends StatefulWidget {
  const InstHeldSecuritiesScreen({super.key});

  @override
  State<InstHeldSecuritiesScreen> createState() => _InstHeldSecuritiesScreenState();
}

class _InstHeldSecuritiesScreenState extends State<InstHeldSecuritiesScreen> {
  List<SecurityRow>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await InstPlanRepository.instance.heldSecurities();
    if (mounted) setState(() => _rows = r);
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final rows = _rows;
    final toReturn = rows?.where((r) => r.shouldReturn).length ?? 0;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Cheques & documents', 'چیک اور کاغذات'),
            rows == null ? '' : Loc.t('${rows.length} with shop • $toReturn to return', '${rows.length} دکان کے پاس • $toReturn واپس کرنے ہیں')),
        Expanded(
          child: rows == null
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(child: Text(Loc.t('No document with the shop.', 'دکان کے پاس کوئی کاغذ نہیں۔'), style: TextStyle(color: p.textMuted)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
                        for (final r in rows)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: instCard(p),
                            child: ListTile(
                              onTap: () async {
                                await Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => InstPlanDetailScreen(planId: r.security.planId)));
                                await _load();
                              },
                              leading: Icon(r.shouldReturn ? Icons.assignment_return_outlined : Icons.lock_outline,
                                  color: r.shouldReturn ? p.amber : p.navy),
                              title: Text('${r.customerName}  •  ${r.planNo}',
                                  style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                [
                                  securityTitle(r.security),
                                  if (r.security.amount > 0) instRs(r.security.amount),
                                  r.shouldReturn
                                      ? '${Loc.t('Plan', 'پلان')} ${planStatusLabel(r.planStatus)} — ${Loc.t('return it', 'واپس کریں')}'
                                      : Loc.t('Plan running', 'پلان جاری'),
                                ].join('  •  '),
                                style: TextStyle(color: r.shouldReturn ? p.amber : p.textMuted, fontSize: 12),
                              ),
                            ),
                          ),
                      ]),
                    ),
        ),
      ]),
    );
  }
}
