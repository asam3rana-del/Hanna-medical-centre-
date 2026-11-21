import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_models.dart';
import 'inst_reports.dart';
import 'inst_repository.dart';
import 'inst_ui.dart';

/// Step 9: maujood stock ka rate badlein (market mein rate barha / ghata).
///
/// Category + search se pieces chunein -> naya rate (seedha raqam / Rs +- / % +-) -> preview (har piece ka purana -> naya,
/// stock ki kul maliyat ka farq) -> lagao. Naqd (bechne ki) qeemat hamesha; khareed (cost) sirf jab "khareed bhi" on ho
/// (maslan supplier ne pichhla bill kam kiya). Har tabdeeli ka record; pehle se bane qist plan nahi badalte.
class InstRateChangeScreen extends StatefulWidget {
  const InstRateChangeScreen({super.key});

  @override
  State<InstRateChangeScreen> createState() => _InstRateChangeScreenState();
}

class _InstRateChangeScreenState extends State<InstRateChangeScreen> {
  List<InstItem> _items = const [];
  List<InstCategory> _cats = const [];
  bool _loaded = false;
  int? _catId;
  String _q = '';
  final Set<int> _unticked = {};
  RateChangeMode _mode = RateChangeMode.percent;
  final _value = TextEditingController();
  final _note = TextEditingController();
  bool _alsoCost = false;
  int _roundTo = 100;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = InstRepository.instance;
    final cats = await repo.categories();
    final items = await repo.items(status: itemInStock);
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _items = items;
      _loaded = true;
    });
  }

  List<InstItem> get _matching => _items.where((i) => (_catId == null || i.categoryId == _catId) && i.matches(_q)).toList();
  List<InstItem> get _selected => _matching.where((i) => !_unticked.contains(i.id)).toList();

  /// Value likhi ho to (purana, naya) har chune piece ka.
  double? get _v {
    final t = _value.text.replaceAll(',', '').trim();
    if (t.isEmpty || t == '-' || t == '+') return null;
    return double.tryParse(t);
  }

  double _newCash(InstItem i) => applyRateChange(i.cashPrice, _mode, _v ?? 0, roundTo: _roundTo);
  double _newCost(InstItem i) => applyRateChange(i.costPrice, _mode, _v ?? 0, roundTo: _roundTo);

  Future<void> _apply() async {
    final sel = _selected;
    if (_v == null) return instToast(context, Loc.t('Enter the new rate / change.', 'نیا ریٹ / تبدیلی لکھیں۔'));
    if (sel.isEmpty) return instToast(context, Loc.t('No piece selected.', 'کوئی پیس نہیں چنا۔'));
    final oldCash = sel.fold<double>(0, (a, i) => a + i.cashPrice);
    final newCash = sel.fold<double>(0, (a, i) => a + _newCash(i));
    final oldCost = sel.fold<double>(0, (a, i) => a + i.costPrice);
    final newCost = sel.fold<double>(0, (a, i) => a + _newCost(i));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('Change rate of ${sel.length} pieces?', '${sel.length} پیس کا ریٹ بدلیں؟')),
        content: Text([
          '${Loc.t('Cash value', 'نقد مالیت')}: ${instRs(oldCash)} → ${instRs(newCash)} (${_signed(newCash - oldCash)})',
          if (_alsoCost) '${Loc.t('Purchase cost', 'خرید لاگت')}: ${instRs(oldCost)} → ${instRs(newCost)} (${_signed(newCost - oldCost)})',
          '',
          Loc.t('Installment plans already made will NOT change.', 'پہلے سے بنے قسط پلان نہیں بدلیں گے۔'),
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Apply', 'لاگو کریں'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final n = await InstRepository.instance.changeRates(
        newCash: {for (final i in sel) i.id!: _newCash(i)},
        newCost: _alsoCost ? {for (final i in sel) i.id!: _newCost(i)} : const {},
        note: _note.text,
      );
      if (!mounted) return;
      instToast(context, Loc.t('$n pieces updated', '$n پیس اپ ڈیٹ ہو گئے'));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        instToast(context, instErr(e));
      }
    }
  }

  String _signed(double v) => v >= 0 ? '+${instRs(v)}' : '-${instRs(-v)}';

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final list = _matching;
    final sel = _selected;
    final hasV = _v != null;
    final diff = hasV ? sel.fold<double>(0, (a, i) => a + _newCash(i) - i.cashPrice) : 0.0;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Change Rates', 'ریٹ بدلیں'), Loc.t('Market rate went up or down', 'مارکیٹ ریٹ بڑھا یا گھٹا')),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                  instSectionTitle(p, Loc.t('1. WHICH PIECES', '1۔ کون سے پیس')),
                  DropdownButtonFormField<int?>(
                    value: _catId,
                    decoration: instDeco(p, Loc.t('Category', 'کیٹیگری')),
                    items: [
                      DropdownMenuItem<int?>(value: null, child: Text(Loc.t('All', 'سب'))),
                      for (final c in _cats) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _catId = v;
                      _unticked.clear();
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (v) => setState(() {
                      _q = v;
                      _unticked.clear();
                    }),
                    decoration: instDeco(p, Loc.t('Company / model (e.g. Samsung A15)', 'کمپنی / ماڈل (مثلاً Samsung A15)'), suffix: const Icon(Icons.search)),
                  ),
                  instSectionTitle(p, Loc.t('2. NEW RATE', '2۔ نیا ریٹ')),
                  SegmentedButton<RateChangeMode>(
                    segments: [
                      ButtonSegment(value: RateChangeMode.percent, label: Text(Loc.t('± %', '± %'))),
                      ButtonSegment(value: RateChangeMode.addAmount, label: Text(Loc.t('± Rs', '± روپے'))),
                      ButtonSegment(value: RateChangeMode.setTo, label: Text(Loc.t('New rate', 'نیا ریٹ'))),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-+]'))],
                    onChanged: (_) => setState(() {}),
                    decoration: instDeco(
                      p,
                      switch (_mode) {
                        RateChangeMode.percent => Loc.t('Change % (e.g. 5 or -3)', 'تبدیلی % (مثلاً 5 یا -3)'),
                        RateChangeMode.addAmount => Loc.t('Change Rs (e.g. 1500 or -2000)', 'تبدیلی روپے (مثلاً 1500 یا -2000)'),
                        RateChangeMode.setTo => Loc.t('New cash price for every selected piece', 'ہر چنے پیس کی نئی نقد قیمت'),
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: _roundTo,
                    decoration: instDeco(p, Loc.t('Round to', 'گول کریں')),
                    items: [
                      for (final r in const [1, 10, 50, 100, 500])
                        DropdownMenuItem(value: r, child: Text(r == 1 ? Loc.t('No rounding', 'گول نہیں') : 'Rs $r')),
                    ],
                    onChanged: (v) => setState(() => _roundTo = v ?? 1),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _alsoCost,
                    onChanged: (v) => setState(() => _alsoCost = v),
                    title: Text(Loc.t('Also change purchase cost', 'خرید لاگت بھی بدلیں')),
                    subtitle: Text(
                      Loc.t('Usually OFF: cost is what you paid. Turn on only if the supplier changed the price of this stock.',
                          'عام طور پر بند: لاگت وہ ہے جو آپ نے دی۔ صرف تب آن کریں جب سپلائر نے اسی اسٹاک کی قیمت بدلی ہو۔'),
                      style: TextStyle(color: p.textMuted, fontSize: 11.5),
                    ),
                  ),
                  TextField(controller: _note, decoration: instDeco(p, Loc.t('Reason (optional)', 'وجہ (اختیاری)'), hint: Loc.t('Company rate increase', 'کمپنی ریٹ بڑھا'))),
                  instSectionTitle(p, Loc.t('3. CHECK', '3۔ دیکھ لیں')),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: instCard(p),
                    child: Row(children: [
                      Expanded(
                        child: Text(Loc.t('${sel.length} of ${list.length} pieces', '${list.length} میں سے ${sel.length} پیس'),
                            style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                      ),
                      if (hasV)
                        Text('${Loc.t('Stock value', 'اسٹاک مالیت')} ${_signed(diff)}',
                            style: TextStyle(color: diff >= 0 ? p.teal : p.red, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(Loc.t('No pieces in stock here.', 'یہاں اسٹاک میں کوئی پیس نہیں۔'),
                          textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
                    ),
                  for (final i in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: instCard(p, 12),
                      child: CheckboxListTile(
                        dense: true,
                        value: !_unticked.contains(i.id),
                        onChanged: (v) => setState(() => v == true ? _unticked.remove(i.id) : _unticked.add(i.id!)),
                        title: Text(i.title.isEmpty ? i.model : i.title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            if (i.primaryId.isNotEmpty) i.primaryId,
                            hasV && !_unticked.contains(i.id)
                                ? '${instRs(i.cashPrice)} → ${instRs(_newCash(i))}${_alsoCost ? '  (${Loc.t('cost', 'لاگت')} ${instRs(i.costPrice)} → ${instRs(_newCost(i))})' : ''}'
                                : instRs(i.cashPrice),
                          ].join('\n'),
                          style: TextStyle(color: p.textMuted, fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  instPrimaryButton(
                    p,
                    _saving ? Loc.t('Saving...', 'محفوظ ہو رہا ہے...') : Loc.t('Apply new rate', 'نیا ریٹ لاگو کریں'),
                    _saving || !hasV || sel.isEmpty ? null : _apply,
                    icon: Icons.price_change_outlined,
                  ),
                ]),
        ),
      ]),
    );
  }
}
