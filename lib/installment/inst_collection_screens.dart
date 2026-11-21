import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import '../widgets/party_avatar.dart';
import 'inst_models.dart';
import 'inst_photo_widgets.dart';
import 'inst_plan_math.dart';
import 'inst_plan_repository.dart';
import 'inst_plans_screen.dart';
import 'inst_purchase_repository.dart';
import 'inst_reports.dart';
import 'inst_repository.dart';
import 'inst_ui.dart';

String _d(int ms) => DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));

Future<void> _call(String phone) async {
  final d = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.isEmpty) return;
  try {
    await launchUrl(Uri(scheme: 'tel', path: d));
  } catch (_) {}
}

// ===================================================================== wasooli list

enum CollectWindow { all, late, today, week, month }

/// Recovery wale ke liye: kis se kitna lena hai (late / aaj / 7 din / 30 din), call + WhatsApp + list share.
class InstCollectionListScreen extends StatefulWidget {
  final CollectWindow initial;
  const InstCollectionListScreen({super.key, this.initial = CollectWindow.all});

  @override
  State<InstCollectionListScreen> createState() => _InstCollectionListScreenState();
}

class _InstCollectionListScreenState extends State<InstCollectionListScreen> {
  List<PlanView> _all = const [];
  bool _loaded = false;
  late CollectWindow _w = widget.initial;
  final int _today = dayStart(DateTime.now());

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = (await InstPlanRepository.instance.list()).where((v) => v.plan.isActive).toList();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loaded = true;
    });
  }

  /// Is window mein lene wali raqam (late hamesha shamil, kyun ke wo bhi abhi leni hai).
  double _amount(PlanView v) => switch (_w) {
        CollectWindow.all => v.status.remaining, // Step 32: har woh customer jis se kuch bhi lena hai
        CollectWindow.late => v.status.overdue,
        CollectWindow.today => v.status.dueNow,
        CollectWindow.week => dueWithin(v.status, _today, 7),
        CollectWindow.month => dueWithin(v.status, _today, 30),
      };

  String _label(CollectWindow w) => switch (w) {
        CollectWindow.all => Loc.t('Everyone who owes', 'سب جن سے لینا ہے'),
        CollectWindow.late => Loc.t('Late only', 'صرف لیٹ'),
        CollectWindow.today => Loc.t('Today (with late)', 'آج (لیٹ سمیت)'),
        CollectWindow.week => Loc.t('Next 7 days', 'اگلے 7 دن'),
        CollectWindow.month => Loc.t('Next 30 days', 'اگلے 30 دن'),
      };

  List<PlanView> get _rows {
    final list = _all.where((v) => _amount(v) > 0.5).toList()
      ..sort((a, b) {
        final c = b.status.daysLate.compareTo(a.status.daysLate);
        if (c != 0) return c;
        return (a.status.next?.dueDate ?? 0).compareTo(b.status.next?.dueDate ?? 0);
      });
    return list;
  }

  Future<void> _share(List<PlanView> rows) async {
    final b = StringBuffer('${Loc.t('Collection list', 'وصولی لسٹ')} — ${_label(_w)} — ${_d(_today)}\n\n');
    var i = 0;
    var total = 0.0;
    for (final v in rows) {
      i++;
      final a = _amount(v);
      total += a;
      b.writeln('$i. ${v.customerName} ${v.customerPhone.isEmpty ? '' : '(${v.customerPhone})'}');
      b.writeln('   ${v.plan.planNo} • ${v.itemTitle} • Rs ${a.round()}${v.status.daysLate > 0 ? ' • ${v.status.daysLate} din late' : ''}');
    }
    b.writeln('\n${Loc.t('Total', 'کل')}: Rs ${total.round()}');
    try {
      await Share.share(b.toString());
    } catch (_) {}
  }

  Future<void> _open(PlanView v) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstPlanDetailScreen(planId: v.plan.id)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final rows = _rows;
    final total = rows.fold<double>(0, (a, v) => a + _amount(v));
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Collection List', 'وصولی لسٹ'), Loc.t('Who to collect from', 'کس سے کتنا لینا ہے'), actions: [
          IconButton(
            tooltip: Loc.t('Share list', 'لسٹ شیئر کریں'),
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            onPressed: rows.isEmpty ? null : () => _share(rows),
          ),
        ]),
        SizedBox(
          height: 50,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [
            for (final w in CollectWindow.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(label: Text(_label(w)), selected: _w == w, onSelected: (_) => setState(() => _w = w)),
              ),
          ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          padding: const EdgeInsets.all(14),
          decoration: instCard(p),
          child: Row(children: [
            Text(Loc.t('${rows.length} customers', '${rows.length} کسٹمر'), style: TextStyle(color: p.textMuted, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(instRs(total), style: TextStyle(color: _w == CollectWindow.late ? p.red : p.navy, fontWeight: FontWeight.bold, fontSize: 18)),
          ]),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(child: Text(Loc.t('Nothing to collect here.', 'یہاں کچھ وصول نہیں کرنا۔'), style: TextStyle(color: p.textMuted)))
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
                        itemCount: rows.length,
                        itemBuilder: (_, i) => _row(p, rows[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _row(AppPalette p, PlanView v) {
    final st = v.status;
    final late = st.daysLate > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(v),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        decoration: instCard(p),
        child: Row(children: [
          PartyAvatar(isCustomer: true, partyId: v.plan.customerId, name: v.customerName, radius: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.customerName, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15)),
              Text('${v.plan.planNo} • ${v.itemTitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 11.5)),
              const SizedBox(height: 2),
              Row(children: [
                Text(instRs(_amount(v)), style: TextStyle(color: late ? p.red : p.navy, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (late)
                  Text(Loc.t('${st.daysLate} days late', '${st.daysLate} دن لیٹ'), style: TextStyle(color: p.red, fontSize: 11.5))
                else if (st.next != null)
                  Text(_d(st.next!.dueDate), style: TextStyle(color: p.textMuted, fontSize: 11.5)),
              ]),
            ]),
          ),
          if (v.customerPhone.isNotEmpty) IconButton(icon: Icon(Icons.call_outlined, color: p.teal), onPressed: () => _call(v.customerPhone)),
          IconButton(icon: Icon(Icons.chat_outlined, color: p.teal), onPressed: () => remindPlan(context, v)),
        ]),
      ),
    );
  }
}

// ===================================================================== defaulters

class InstDefaultersScreen extends StatefulWidget {
  final int minDays;
  const InstDefaultersScreen({super.key, this.minDays = 30});

  @override
  State<InstDefaultersScreen> createState() => _InstDefaultersScreenState();
}

class _InstDefaultersScreenState extends State<InstDefaultersScreen> {
  List<PlanView> _all = const [];
  Map<int, List<Guarantor>> _g = const {};
  bool _loaded = false;
  late int _minDays = widget.minDays;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = (await InstPlanRepository.instance.list()).where((v) => v.plan.isActive && v.status.overdue > 0.5).toList();
    final g = <int, List<Guarantor>>{};
    for (final v in list) {
      final all = await InstRepository.instance.guarantors(v.plan.customerId);
      g[v.plan.id] = all.where((x) => v.plan.guarantorIds.contains(x.id)).toList();
    }
    if (!mounted) return;
    setState(() {
      _all = list;
      _g = g;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final rows = _all.where((v) => v.status.daysLate >= _minDays).toList()..sort((a, b) => b.status.daysLate.compareTo(a.status.daysLate));
    final total = rows.fold<double>(0, (a, v) => a + v.status.overdue);
    final remaining = rows.fold<double>(0, (a, v) => a + v.status.remaining);
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Defaulters', 'ڈیفالٹرز'), Loc.t('Late customers and their guarantors', 'لیٹ کسٹمر اور ان کے ضامن')),
        SizedBox(
          height: 50,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [
            for (final d in const [1, 7, 15, 30, 60, 90])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(Loc.t('$d+ days', '$d+ دن')),
                  selected: _minDays == d,
                  onSelected: (_) => setState(() => _minDays = d),
                ),
              ),
          ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          padding: const EdgeInsets.all(14),
          decoration: instCard(p),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Loc.t('${rows.length} defaulters', '${rows.length} ڈیفالٹر'), style: TextStyle(color: p.textMuted, fontWeight: FontWeight.bold)),
                Text('${Loc.t('Total remaining', 'کل باقی')} ${instRs(remaining)}', style: TextStyle(color: p.textMuted, fontSize: 12)),
              ]),
            ),
            Text(instRs(total), style: TextStyle(color: p.red, fontWeight: FontWeight.bold, fontSize: 18)),
          ]),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(child: Text(Loc.t('No defaulters. 👍', 'کوئی ڈیفالٹر نہیں۔ 👍'), style: TextStyle(color: p.textMuted)))
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
                        itemCount: rows.length,
                        itemBuilder: (_, i) => _card(p, rows[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _card(AppPalette p, PlanView v) {
    final st = v.status;
    final lastPay = v.payments.isEmpty ? null : v.payments.first.paidAt;
    final gs = _g[v.plan.id] ?? const <Guarantor>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: instCard(p),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstPlanDetailScreen(planId: v.plan.id)));
            await _reload();
          },
          child: Row(children: [
            PartyAvatar(isCustomer: true, partyId: v.plan.customerId, name: v.customerName, radius: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.customerName, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15.5)),
                Text('${v.plan.planNo} • ${v.itemTitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 11.5)),
                Text(
                  lastPay == null
                      ? Loc.t('No payment yet', 'ابھی کوئی ادائیگی نہیں')
                      : '${Loc.t('Last paid', 'آخری ادائیگی')} ${_d(lastPay)}',
                  style: TextStyle(color: p.textMuted, fontSize: 11.5),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(instRs(st.overdue), style: TextStyle(color: p.red, fontWeight: FontWeight.bold, fontSize: 15)),
              Text(Loc.t('${st.daysLate} days • ${st.overdueCount} qist', '${st.daysLate} دن • ${st.overdueCount} قسط'),
                  style: TextStyle(color: p.red, fontSize: 11)),
            ]),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          if (v.customerPhone.isNotEmpty)
            TextButton.icon(onPressed: () => _call(v.customerPhone), icon: const Icon(Icons.call_outlined, size: 18), label: Text(Loc.t('Call', 'کال'))),
          TextButton.icon(onPressed: () => remindPlan(context, v), icon: const Icon(Icons.chat_outlined, size: 18), label: Text(Loc.t('WhatsApp', 'واٹس ایپ'))),
        ]),
        if (gs.isNotEmpty) ...[
          const Divider(height: 10),
          for (final g in gs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                KycAvatar(owner: 'g', id: g.id!, name: g.name, radius: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${Loc.t('Guarantor', 'ضامن')}: ${g.name}${g.relation.isNotEmpty ? ' (${g.relation})' : ''}',
                      style: TextStyle(color: p.textDark, fontSize: 12.5)),
                ),
                if (g.phone.isNotEmpty) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.call_outlined, color: p.amber, size: 20),
                    onPressed: () => _call(g.phone),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.chat_outlined, color: p.amber, size: 20),
                    tooltip: Loc.t('Message guarantor', 'ضامن کو میسج'),
                    onPressed: () => remindPlan(context, v, phone: g.phone),
                  ),
                ],
              ]),
            ),
        ] else
          Text(Loc.t('No guarantor on this plan', 'اس پلان پر کوئی ضامن نہیں'), style: TextStyle(color: p.red, fontSize: 11.5)),
      ]),
    );
  }
}

// ===================================================================== reports

enum ReportPeriod { thisMonth, lastMonth, thisYear, custom }

class InstReportsScreen extends StatefulWidget {
  const InstReportsScreen({super.key});

  @override
  State<InstReportsScreen> createState() => _InstReportsScreenState();
}

class _InstReportsScreenState extends State<InstReportsScreen> {
  ReportPeriod _period = ReportPeriod.thisMonth;
  late int _from;
  late int _to;
  PeriodReport? _r;
  AgingBuckets _aging = const AgingBuckets();
  int _active = 0;
  int _inStock = 0;
  double _stockCost = 0;
  int _repossessedStock = 0;
  ProfitReport? _profit;
  StockValue _stock = const StockValue(0, 0, 0);
  (int, double, double) _rates = (0, 0.0, 0.0);
  PurchaseSummary _buy = const PurchaseSummary();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _setPeriod(ReportPeriod.thisMonth);
  }

  void _setPeriod(ReportPeriod p, {DateTimeRange? custom}) {
    final now = DateTime.now();
    switch (p) {
      case ReportPeriod.thisMonth:
        final m = monthRange(now);
        _from = m.$1;
        _to = m.$2;
      case ReportPeriod.lastMonth:
        final m = monthRange(DateTime(now.year, now.month - 1, 1));
        _from = m.$1;
        _to = m.$2;
      case ReportPeriod.thisYear:
        _from = DateTime(now.year, 1, 1).millisecondsSinceEpoch;
        _to = DateTime(now.year + 1, 1, 1).millisecondsSinceEpoch;
      case ReportPeriod.custom:
        final c = custom!;
        _from = dayStart(c.start);
        _to = DateTime(c.end.year, c.end.month, c.end.day + 1).millisecondsSinceEpoch;
    }
    _period = p;
    _loading = true;
    _load(); // setState sirf await ke baad (initState / setState ke andar se bhi mehfooz)
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: DateTimeRange(start: DateTime.fromMillisecondsSinceEpoch(_from), end: now),
    );
    if (r != null) setState(() => _setPeriod(ReportPeriod.custom, custom: r));
  }

  Future<void> _load() async {
    final repo = InstPlanRepository.instance;
    final r = await repo.report(from: _from, to: _to);
    final today = dayStart(DateTime.now());
    final active = (await repo.list(today: today)).where((v) => v.plan.isActive).toList();
    final stock = await InstRepository.instance.items();
    final profit = await repo.profit(from: _from, to: _to);
    final sv = await InstRepository.instance.stockValue();
    final rates = await InstRepository.instance.priceChangeSummary(from: _from, to: _to);
    final buy = await InstPurchaseRepository.instance.summary(from: _from, to: _to);
    if (!mounted) return;
    setState(() {
      _r = r;
      _profit = profit;
      _stock = sv;
      _rates = rates;
      _buy = buy;
      _active = active.length;
      _aging = agingOf(active.map((v) => v.status), today);
      _inStock = stock.where((i) => i.status == itemInStock).length;
      _stockCost = stock.where((i) => i.status == itemInStock).fold<double>(0, (a, i) => a + i.costPrice);
      _repossessedStock = stock.where((i) => i.status == itemRepossessed).length;
      _loading = false;
    });
  }

  String _periodLabel(ReportPeriod p) => switch (p) {
        ReportPeriod.thisMonth => Loc.t('This month', 'اس مہینے'),
        ReportPeriod.lastMonth => Loc.t('Last month', 'پچھلے مہینے'),
        ReportPeriod.thisYear => Loc.t('This year', 'اس سال'),
        ReportPeriod.custom => Loc.t('Dates...', 'تاریخیں...'),
      };

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final r = _r;
    final showMoney = Session.isAdminOrManager;
    final range = '${_d(_from)} – ${_d(DateTime.fromMillisecondsSinceEpoch(_to).subtract(const Duration(days: 1)).millisecondsSinceEpoch)}';
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Installment Reports', 'قسط رپورٹس'), range),
        SizedBox(
          height: 50,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [
            for (final pr in ReportPeriod.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(_periodLabel(pr)),
                  selected: _period == pr,
                  onSelected: (_) {
                    if (pr == ReportPeriod.custom) {
                      _pickCustom();
                    } else {
                      setState(() => _setPeriod(pr));
                    }
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: _loading || r == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                  if (showMoney && _profit != null) ...[
                    instSectionTitle(p, Loc.t('PROFIT', 'منافع')),
                    _profitCard(p, _profit!),
                  ],
                  instSectionTitle(p, Loc.t('COLLECTION', 'وصولی')),
                  _card(p, [
                    _big(p, Loc.t('Total collected', 'کل وصولی'), instRs(r.collectedTotal), p.teal),
                    _line(p, Loc.t('Installments', 'قسطیں'), instRs(r.collectedInstallments)),
                    _line(p, Loc.t('Advance', 'ایڈوانس'), instRs(r.collectedAdvance)),
                    _line(p, Loc.t('Late fines', 'لیٹ جرمانہ'), instRs(r.collectedFines)),
                    if (r.discounts > 0.5)
                      _line(p, Loc.t('Discount given (no cash)', 'رعایت دی (کیش نہیں)'), instRs(r.discounts), c: p.red),
                    const Divider(),
                    _line(p, Loc.t('Cash', 'کیش'), instRs(r.cashIn)),
                    _line(p, Loc.t('Bank', 'بینک'), instRs(r.bankIn)),
                    _line(p, Loc.t('Payments', 'ادائیگیاں'), '${r.paymentCount}'),
                  ]),
                  if (r.byDay.isNotEmpty) ...[
                    instSectionTitle(p, Loc.t('BY DAY', 'روزانہ')),
                    _card(p, [_dayBars(p, r.byDay)]),
                  ],
                  instSectionTitle(p, Loc.t('NEW PLANS', 'نئے پلان')),
                  _card(p, [
                    _big(p, Loc.t('Plans made', 'بنے پلان'), '${r.newPlans}', p.navy),
                    _line(p, Loc.t('Cash value', 'نقد مالیت'), instRs(r.newCashValue)),
                    _line(p, Loc.t('Installment value', 'قسط مالیت'), instRs(r.newTotalValue)),
                    if (showMoney) ...[
                      _line(p, Loc.t('Purchase cost', 'خرید لاگت'), instRs(r.newCost)),
                      _line(p, Loc.t('Expected profit', 'متوقع منافع'), instRs(r.newExpectedProfit), c: p.teal),
                    ],
                    const Divider(),
                    _line(p, Loc.t('Completed in period', 'اس دوران مکمل'), '${r.completed}'),
                    _line(p, Loc.t('Items taken back', 'سامان واپس'), '${r.repossessed}', c: r.repossessed > 0 ? p.red : null),
                  ]),
                  instSectionTitle(p, Loc.t('RECEIVABLE NOW', 'ابھی کل باقی')),
                  _card(p, [
                    _big(p, Loc.t('Total remaining', 'کل باقی'), instRs(_aging.total), p.navy),
                    _line(p, Loc.t('Active plans', 'جاری پلان'), '$_active'),
                    _line(p, Loc.t('Not late yet', 'ابھی لیٹ نہیں'), instRs(_aging.notLate)),
                    _line(p, Loc.t('1–30 days late', '1–30 دن لیٹ'), instRs(_aging.d1to30), c: p.amber),
                    _line(p, Loc.t('31–60 days late', '31–60 دن لیٹ'), instRs(_aging.d31to60), c: p.orange),
                    _line(p, Loc.t('61–90 days late', '61–90 دن لیٹ'), instRs(_aging.d61to90), c: p.red),
                    _line(p, Loc.t('90+ days late', '90+ دن لیٹ'), instRs(_aging.d90plus), c: p.red),
                    if (_aging.total > 0) ...[const SizedBox(height: 8), _agingBar(p)],
                  ]),
                  instSectionTitle(p, Loc.t('STOCK', 'اسٹاک')),
                  _card(p, [
                    _line(p, Loc.t('Pieces in stock', 'اسٹاک میں پیس'), '$_inStock'),
                    if (showMoney) _line(p, Loc.t('Stock cost', 'اسٹاک کی لاگت'), instRs(_stockCost)),
                    _line(p, Loc.t('Stock at cash price', 'نقد قیمت پر اسٹاک'), instRs(_stock.cash)),
                    if (showMoney)
                      _line(p, Loc.t('Margin in stock (cash − cost)', 'اسٹاک میں منافع (نقد − لاگت)'), instRs(_stock.margin),
                          c: _stock.margin >= 0 ? p.teal : p.red),
                    _line(p, Loc.t('Taken-back pieces', 'واپس لیے پیس'), '$_repossessedStock'),
                    if (_rates.$1 > 0) ...[
                      const Divider(),
                      _line(p, Loc.t('Rate changes in period', 'اس دوران ریٹ تبدیلیاں'), '${_rates.$1}'),
                      _line(p, Loc.t('Cash value change', 'نقد مالیت میں فرق'), _signedRs(_rates.$2), c: _rates.$2 >= 0 ? p.teal : p.red),
                      if (showMoney && _rates.$3.abs() >= 0.005)
                        _line(p, Loc.t('Cost value change', 'لاگت میں فرق'), _signedRs(_rates.$3), c: _rates.$3 <= 0 ? p.teal : p.red),
                    ],
                  ]),
                  if (showMoney) ...[
                    instSectionTitle(p, Loc.t('PURCHASES', 'خریداری')),
                    _card(p, [
                      _line(p, Loc.t('Bills in period', 'اس دوران بل'), '${_buy.bills}  (${_buy.pieces} ${Loc.t('pcs', 'پیس')})'),
                      _line(p, Loc.t('Bought (cost)', 'خریداری (لاگت)'), instRs(_buy.total)),
                      _line(p, Loc.t('Paid to suppliers', 'سپلائرز کو ادا'), instRs(_buy.paid), c: p.teal),
                      const Divider(),
                      _line(p, Loc.t('To pay suppliers now', 'ابھی سپلائرز کو دینا'), instRs(_buy.payable),
                          c: _buy.payable > 0.5 ? p.red : p.teal),
                    ]),
                  ],
                ]),
        ),
      ]),
    );
  }

  String _signedRs(double v) => v >= 0 ? '+${instRs(v)}' : '-${instRs(-v)}';

  Widget _profitCard(AppPalette p, ProfitReport pr) {
    final ex = pr.expenses.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return _card(p, [
      _big(p, Loc.t('Net profit', 'خالص منافع'), _signedRs(pr.netProfit), pr.netProfit >= 0 ? p.teal : p.red),
      _line(p, Loc.t('Profit in collections', 'وصولی میں منافع'), instRs(pr.realizedProfit), c: pr.realizedProfit >= 0 ? p.teal : p.red),
      _line(p, Loc.t('Late fines', 'لیٹ جرمانہ'), instRs(pr.fines)),
      if (pr.discounts > 0.5)
        _line(p, Loc.t('Discount given (already taken out of profit)', 'رعایت دی (منافع سے کٹ چکی)'), '− ${instRs(pr.discounts)}', c: p.red),
      if (pr.cashSales > 0.5)
        _line(p, '${Loc.t('Cash sale profit', 'نقد سیل منافع')} (${instRs(pr.cashSales)})', instRs(pr.cashSaleProfit),
            c: pr.cashSaleProfit >= 0 ? p.teal : p.red),
      _line(p, Loc.t('Gross profit', 'کل منافع'), instRs(pr.grossProfit)),
      const Divider(),
      for (final e in ex) _line(p, e.key, '- ${instRs(e.value)}', c: p.red),
      _line(p, Loc.t('Total expenses', 'کل خرچے'), '- ${instRs(pr.expenseTotal)}', c: p.red),
      const SizedBox(height: 6),
      Text(
        Loc.t('Each installment carries its share of profit: amount × (installment price − cost) ÷ installment price. '
            'Expenses include salary, rent and bills.',
            'ہر قسط میں منافع کا حصہ: رقم × (قسط قیمت − لاگت) ÷ قسط قیمت۔ خرچوں میں تنخواہ، کرایہ اور بل شامل ہیں۔'),
        style: TextStyle(color: p.textMuted, fontSize: 11),
      ),
      if (pr.collectedWithoutCost > 0.5)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            Loc.t('${instRs(pr.collectedWithoutCost)} collected on items without purchase cost — their profit is not counted.',
                '${instRs(pr.collectedWithoutCost)} کی وصولی ایسے سامان کی جس کی خرید قیمت نہیں لکھی — اس کا منافع شامل نہیں۔'),
            style: TextStyle(color: p.amber, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ),
    ]);
  }

  Widget _card(AppPalette p, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: instCard(p),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _big(AppPalette p, String label, String value, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: p.textMuted, fontWeight: FontWeight.bold))),
          Text(value, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 20)),
        ]),
      );

  Widget _line(AppPalette p, String label, String value, {Color? c}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: p.textMuted))),
          Text(value, style: TextStyle(color: c ?? p.textDark, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _agingBar(AppPalette p) {
    final parts = <(double, Color)>[
      (_aging.notLate, p.teal),
      (_aging.d1to30, p.amber),
      (_aging.d31to60, p.orange),
      (_aging.d61to90 + _aging.d90plus, p.red),
    ].where((e) => e.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        child: Row(children: [
          for (final (v, c) in parts) Expanded(flex: (v / _aging.total * 1000).round().clamp(1, 1000).toInt(), child: Container(color: c)),
        ]),
      ),
    );
  }

  Widget _dayBars(AppPalette p, Map<int, double> byDay) {
    final days = byDay.keys.toList()..sort();
    final max = byDay.values.fold<double>(0, (a, b) => b > a ? b : a);
    return Column(children: [
      for (final d in days.reversed.take(31))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 62, child: Text(DateFormat('dd MMM').format(DateTime.fromMillisecondsSinceEpoch(d)), style: TextStyle(color: p.textMuted, fontSize: 12))),
            Expanded(
              child: LayoutBuilder(
                builder: (_, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 10,
                    width: max <= 0 ? 0 : c.maxWidth * (byDay[d]! / max),
                    decoration: BoxDecoration(color: p.teal.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: Text(instRs(byDay[d]!), textAlign: TextAlign.right, style: TextStyle(color: p.textDark, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
    ]);
  }
}
