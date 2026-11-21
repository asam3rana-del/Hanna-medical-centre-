import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_cash_sale_repository.dart';
import 'inst_cash_sale_screens.dart';
import 'inst_collection_screens.dart';
import 'inst_customers_screen.dart';
import 'inst_ledger_reports.dart';
import 'inst_pdf.dart';
import 'inst_plan_math.dart';
import 'inst_plan_repository.dart';
import 'inst_plans_screen.dart';
import 'inst_purchase_repository.dart';
import 'inst_purchase_screens.dart';
import 'inst_repository.dart';
import 'inst_reports.dart' show monthRange;
import 'inst_ui.dart';

/// Reports hub: karobar ki surat (lena / stock / dena) + har report ka rasta.
/// Nayi reports: Sale, Stock, Qisten (aane wali), Lena (customer wise). Purani: Munafa & Wasooli, Late, Suppliers, Khareed.

String _d(int ms) => ms <= 0 ? '—' : DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));
String _dShort(int ms) => ms <= 0 ? '—' : DateFormat('dd MMM').format(DateTime.fromMillisecondsSinceEpoch(ms));

Future<void> _share(BuildContext context, String text) async {
  try {
    await Share.share(text);
  } catch (e) {
    if (context.mounted) instToast(context, instErr(e));
  }
}

Widget _card(AppPalette p, List<Widget> children) => Container(
      padding: const EdgeInsets.all(14),
      decoration: instCard(p),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );

Widget _line(AppPalette p, String label, String value, {Color? c, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: p.textMuted, fontSize: 13.5))),
        Text(value, style: TextStyle(color: c ?? p.textDark, fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 16 : 14)),
      ]),
    );

Widget _empty(AppPalette p, String text) => Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted))),
    );

// ===================================================================== period chips

/// Muddat chunne ki chips. [future] = aage ki tareekhen (qist report).
class _RangeBar extends StatefulWidget {
  final bool future;
  final void Function(int from, int to, String label) onChanged;
  const _RangeBar({required this.onChanged, this.future = false});

  @override
  State<_RangeBar> createState() => _RangeBarState();
}

class _RangeBarState extends State<_RangeBar> {
  int _sel = 0;

  List<(String, (int, int) Function())> get _presets {
    final now = DateTime.now();
    final today = dayStart(now);
    int plusDays(int n) => DateTime(now.year, now.month, now.day + n).millisecondsSinceEpoch;
    if (widget.future) {
      return [
        (Loc.t('Today', 'آج'), () => (today, plusDays(1))),
        (Loc.t('7 days', '7 دن'), () => (today, plusDays(7))),
        (Loc.t('This month', 'اس مہینے'), () => monthRange(now)),
        (Loc.t('Next month', 'اگلے مہینے'), () => monthRange(DateTime(now.year, now.month + 1, 1))),
      ];
    }
    return [
      (Loc.t('This month', 'اس مہینے'), () => monthRange(now)),
      (Loc.t('Last month', 'پچھلے مہینے'), () => monthRange(DateTime(now.year, now.month - 1, 1))),
      (Loc.t('This year', 'اس سال'), () => (DateTime(now.year, 1, 1).millisecondsSinceEpoch, DateTime(now.year + 1, 1, 1).millisecondsSinceEpoch)),
      (Loc.t('Today', 'آج'), () => (today, plusDays(1))),
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick(0));
  }

  void _pick(int i) {
    final ps = _presets;
    final r = ps[i].$2();
    setState(() => _sel = i);
    widget.onChanged(r.$1, r.$2, ps[i].$1);
  }

  Future<void> _custom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: widget.future ? DateTime(now.year + 3) : now,
    );
    if (r == null || !mounted) return;
    setState(() => _sel = -1);
    widget.onChanged(dayStart(r.start), DateTime(r.end.year, r.end.month, r.end.day + 1).millisecondsSinceEpoch,
        '${DateFormat('dd MMM').format(r.start)} – ${DateFormat('dd MMM yy').format(r.end)}');
  }

  @override
  Widget build(BuildContext context) {
    final ps = _presets;
    return SizedBox(
      height: 48,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
        for (var i = 0; i < ps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(label: Text(ps[i].$1), selected: _sel == i, onSelected: (_) => _pick(i)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(Loc.t('Dates...', 'تاریخیں...')),
            selected: _sel == -1,
            onSelected: (_) => _custom(),
          ),
        ),
      ]),
    );
  }
}

// ===================================================================== hub

class InstReportsHubScreen extends StatefulWidget {
  const InstReportsHubScreen({super.key});

  @override
  State<InstReportsHubScreen> createState() => _InstReportsHubScreenState();
}

class _InstReportsHubScreenState extends State<InstReportsHubScreen> {
  BusinessPosition _pos = const BusinessPosition();
  int _lateCustomers = 0;
  double _dueWeek = 0;
  int _stockPieces = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = dayStart(DateTime.now());
    final views = await InstPlanRepository.instance.list(today: today);
    final sv = await InstRepository.instance.stockValue();
    final buy = await InstPurchaseRepository.instance.summary(from: today, to: today);
    final money = await InstRepository.instance.cashBalances();
    final rec = receivables(views);
    final week = dueEntries(views, from: today, to: DateTime.fromMillisecondsSinceEpoch(today).add(const Duration(days: 7)).millisecondsSinceEpoch, today: today);
    if (!mounted) return;
    setState(() {
      _pos = BusinessPosition(
        receivable: rec.fold<double>(0, (a, r) => a + r.remaining),
        overdue: rec.fold<double>(0, (a, r) => a + r.overdue),
        stockCost: sv.cost,
        stockCash: sv.cash,
        payable: buy.payable,
        cash: money.$1,
        bank: money.$2,
      );
      _lateCustomers = rec.where((r) => r.overdue > 0.5).length;
      _dueWeek = week.fold<double>(0, (a, e) => a + e.remaining);
      _stockPieces = sv.pieces;
      _loaded = true;
    });
  }

  Future<void> _open(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final tiles = <(IconData, String, String, Color, Widget)>[
      (Icons.trending_up, Loc.t('Profit & Collection', 'منافع اور وصولی'), Loc.t('Profit, expenses, aging', 'منافع، خرچے، باقی'), p.teal,
          const InstReportsScreen()),
      (Icons.point_of_sale, Loc.t('Sale Report', 'سیل رپورٹ'), Loc.t('Installment + cash', 'قسط + نقد'), p.blue, const InstSaleReportScreen()),
      (Icons.inventory_2_outlined, Loc.t('Stock Report', 'اسٹاک رپورٹ'), Loc.t('By category, age', 'کیٹیگری، پرانا مال'), p.purple,
          const InstStockReportScreen()),
      (Icons.event_note_outlined, Loc.t('Due Installments', 'آنے والی قسطیں'), Loc.t('Date-wise', 'تاریخ وار'), p.navyLight,
          const InstDueReportScreen()),
      (Icons.report_gmailerrorred_outlined, Loc.t('Late Payments', 'لیٹ ادائیگیاں'), Loc.t('Defaulters', 'ڈیفالٹرز'), p.red,
          const InstDefaultersScreen(minDays: 1)),
      (Icons.call_received, Loc.t('Receivable', 'لینا ہے'), Loc.t('Customer-wise', 'کسٹمر وار'), p.orange, const InstReceivableScreen()),
      (Icons.call_made, Loc.t('Payable', 'دینا ہے'), Loc.t('Suppliers', 'سپلائرز'), p.amber, const InstSuppliersScreen()),
      (Icons.local_shipping_outlined, Loc.t('Purchase History', 'خریداری کی ہسٹری'), Loc.t('Bills by date', 'تاریخ وار بل'), p.tealDark,
          const InstPurchaseReportScreen()),
      (Icons.assignment_return_outlined, Loc.t('Returns History', 'واپسی کی ہسٹری'), Loc.t('Sale / qist / purchase', 'سیل / قسط / خریداری'), p.orange,
          const InstReturnsReportScreen()),
    ];
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 900 ? 4 : (width >= 600 ? 3 : 2);
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Reports', 'رپورٹس'), Loc.t('Everything in one place', 'سب کچھ ایک جگہ')),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
              if (!_loaded)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else
                _card(p, [
                  Text(Loc.t('BUSINESS POSITION', 'کاروبار کی صورت'),
                      style: TextStyle(color: p.textMuted, fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  _line(p, Loc.t('Receivable from customers', 'کسٹمرز سے لینا'), instRs(_pos.receivable), c: p.teal),
                  _line(p, Loc.t('  of which late ($_lateCustomers customers)', '  اس میں لیٹ ($_lateCustomers کسٹمر)'),
                      instRs(_pos.overdue), c: _pos.overdue > 0.5 ? p.red : p.textMuted),
                  _line(p, Loc.t('  due in next 7 days', '  اگلے 7 دن میں'), instRs(_dueWeek)),
                  _line(p, Loc.t('Stock at cost ($_stockPieces pcs)', 'اسٹاک لاگت پر ($_stockPieces پیس)'), instRs(_pos.stockCost)),
                  _line(p, Loc.t('Cash in hand', 'ہاتھ میں کیش'), instRs(_pos.cash), c: _pos.cash < 0 ? p.red : null),
                  _line(p, Loc.t('In bank', 'بینک میں'), instRs(_pos.bank), c: _pos.bank < 0 ? p.red : null),
                  _line(p, Loc.t('Payable to suppliers', 'سپلائرز کو دینا'), instRs(_pos.payable), c: _pos.payable > 0.5 ? p.red : p.textMuted),
                  const Divider(),
                  _line(p, Loc.t('Net worth (all above − payable)', 'خالص مالیت (سب − دینا)'), instRs(_pos.net),
                      c: _pos.net >= 0 ? p.teal : p.red, bold: true),
                  Text(
                      Loc.t('Cash / bank = all cash-in minus cash-out entered in the app. Add your starting cash once from Shop tools > Cash.',
                          'کیش / بینک = ایپ میں درج سب آمد منفی خرچ۔ شروع کا کیش ایک بار دکان کے ٹولز > کیش سے ڈالیں۔'),
                      style: TextStyle(color: p.textMuted, fontSize: 11)),
                ]),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  for (final t in tiles)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _open(t.$5),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: instCard(p),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Icon(t.$1, color: t.$4, size: 26),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(t.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 11.5)),
                          ]),
                        ]),
                      ),
                    ),
                ],
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ===================================================================== sale report

class InstSaleReportScreen extends StatefulWidget {
  const InstSaleReportScreen({super.key});

  @override
  State<InstSaleReportScreen> createState() => _InstSaleReportScreenState();
}

class _InstSaleReportScreenState extends State<InstSaleReportScreen> {
  List<SaleRow> _rows = const [];
  Map<int, String> _cats = const {};
  String _label = '';
  bool _loaded = false;

  Future<void> _load(int from, int to, String label) async {
    final views = await InstPlanRepository.instance.list();
    final cash = await InstCashSaleRepository.instance.list(from: from, to: to);
    final cats = await InstRepository.instance.categories();
    if (!mounted) return;
    setState(() {
      _rows = [...saleRows(views, from: from, to: to), ...cashSaleRows(cash, from: from, to: to)]
        ..sort((a, b) => b.date.compareTo(a.date));
      _cats = {for (final c in cats) if (c.id != null) c.id!: c.name};
      _label = label;
      _loaded = true;
    });
  }

  String _text(SaleTotals t, bool money) {
    final b = StringBuffer('${Loc.t('Sale Report', 'سیل رپورٹ')} — $_label\n');
    b.writeln('${Loc.t('Installment plans', 'قسط پلان')}: ${t.planCount}');
    if (t.cashCount > 0) b.writeln('${Loc.t('Cash sales', 'نقد سیل')}: ${t.cashCount} (${instRs(t.cashValue)})');
    b.writeln('${Loc.t('Total sale value', 'کل سیل مالیت')}: ${instRs(t.total)}');
    b.writeln('${Loc.t('Advance', 'ایڈوانس')}: ${instRs(t.advance)}');
    if (money) b.writeln('${Loc.t('Expected profit', 'متوقع منافع')}: ${instRs(t.profit)}');
    b.writeln();
    for (final r in _rows) {
      b.writeln('${_dShort(r.date)}  ${r.planNo}  ${r.customer} — ${r.item}  ${instRs(r.totalPrice)}');
    }
    return b.toString();
  }

  Future<void> _pdf(SaleTotals t, bool money) => InstPdf.shareTable(
        context,
        base: 'Sale_Report',
        title: Loc.t('Sale Report', 'سیل رپورٹ'),
        sub: _label,
        summary: [
          (Loc.t('Pieces sold', 'بکے پیس'), '${t.count}  (${Loc.t('cash', 'نقد')} ${t.cashCount})'),
          (Loc.t('Total sale value', 'کل سیل مالیت'), instRs(t.total)),
          (Loc.t('Received upfront', 'فوری ملا'), instRs(t.advance)),
          if (money) (Loc.t('Expected profit', 'متوقع منافع'), instRs(t.profit)),
        ],
        headers: [
          Loc.t('Date', 'تاریخ'),
          Loc.t('No.', 'نمبر'),
          Loc.t('Customer', 'کسٹمر'),
          Loc.t('Item', 'سامان'),
          Loc.t('Value', 'مالیت'),
          if (money) Loc.t('Profit', 'منافع'),
        ],
        flex: money ? const [2, 2, 3, 4, 2, 2] : const [2, 2, 3, 4, 2],
        right: money ? const {4, 5} : const {4},
        rows: [
          for (final r in _rows)
            [
              _dShort(r.date),
              r.planNo,
              r.customer,
              [r.item, if (r.itemId.isNotEmpty) r.itemId].join(' '),
              instRs(r.totalPrice),
              if (money) r.hasCost ? instRs(r.expectedProfit) : '—',
            ]
        ],
      );

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final money = Session.isAdminOrManager;
    final t = saleTotals(_rows);
    final byCat = <String, (int, double)>{};
    for (final r in _rows) {
      final n = _cats[r.categoryId] ?? '—';
      final c = byCat[n] ?? (0, 0.0);
      byCat[n] = (c.$1 + 1, c.$2 + r.totalPrice);
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Sale Report', 'سیل رپورٹ'), _label, actions: [
          IconButton(
            tooltip: Loc.t('Share', 'شیئر'),
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            onPressed: _rows.isEmpty ? null : () => _share(context, _text(t, money)),
          ),
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
            onPressed: _rows.isEmpty ? null : () => _pdf(t, money),
          ),
        ]),
        _RangeBar(onChanged: _load),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 32), children: [
                  _card(p, [
                    _line(p, Loc.t('Pieces sold', 'بکے پیس'), '${t.count}', bold: true),
                    _line(p, Loc.t('  on installments', '  قسط پر'), '${t.planCount}  •  ${instRs(t.total - t.cashValue)}'),
                    _line(p, Loc.t('  for cash', '  نقد'), '${t.cashCount}  •  ${instRs(t.cashValue)}'),
                    _line(p, Loc.t('Total sale value', 'کل سیل مالیت'), instRs(t.total)),
                    _line(p, Loc.t('Cash price value', 'نقد قیمت پر مالیت'), instRs(t.cash)),
                    _line(p, Loc.t('Received upfront (advance + cash)', 'فوری ملا (ایڈوانس + نقد)'), instRs(t.advance)),
                    if (money) ...[
                      _line(p, Loc.t('Purchase cost', 'خرید لاگت'), instRs(t.cost)),
                      _line(p, Loc.t('Expected profit', 'متوقع منافع'), instRs(t.profit), c: p.teal, bold: true),
                      if (t.withoutCost > 0)
                        Text(Loc.t('${t.withoutCost} plans have no purchase cost — not in profit.', '${t.withoutCost} پلانز کی خرید قیمت نہیں — منافع میں شامل نہیں۔'),
                            style: TextStyle(color: p.amber, fontSize: 11.5)),
                    ],
                  ]),
                  if (byCat.length > 1) ...[
                    instSectionTitle(p, Loc.t('BY CATEGORY', 'کیٹیگری وار')),
                    _card(p, [for (final e in byCat.entries) _line(p, '${e.key} (${e.value.$1})', instRs(e.value.$2))]),
                  ],
                  instSectionTitle(p, Loc.t('PLANS', 'پلان')),
                  if (_rows.isEmpty) _empty(p, Loc.t('No sales in this period.', 'اس دوران کوئی سیل نہیں۔')),
                  for (final r in _rows)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: instCard(p),
                      child: ListTile(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                r.isCash ? InstCashSaleDetailScreen(saleId: r.cashSaleId!) : InstPlanDetailScreen(planId: r.planId))),
                        leading: Icon(r.isCash ? Icons.payments_outlined : Icons.request_quote_outlined, color: r.isCash ? p.teal : p.blue),
                        title: Text('${r.customer} — ${r.item}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          [_d(r.date), r.planNo, if (r.itemId.isNotEmpty) r.itemId].join('  •  '),
                          style: TextStyle(color: p.textMuted, fontSize: 12),
                        ),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(instRs(r.totalPrice), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                          if (money && r.hasCost)
                            Text('+${instRs(r.expectedProfit)}', style: TextStyle(color: p.teal, fontSize: 11.5)),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ===================================================================== stock report

class InstStockReportScreen extends StatefulWidget {
  const InstStockReportScreen({super.key});

  @override
  State<InstStockReportScreen> createState() => _InstStockReportScreenState();
}

class _InstStockReportScreenState extends State<InstStockReportScreen> {
  StockReport? _r;
  int? _age; // bucket filter

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await InstRepository.instance.items();
    final cats = await InstRepository.instance.categories();
    if (!mounted) return;
    setState(() => _r = stockReport(items, {for (final c in cats) if (c.id != null) c.id!: c.name}, dayStart(DateTime.now())));
  }

  String _text(StockReport r, bool money) {
    final b = StringBuffer('${Loc.t('Stock Report', 'اسٹاک رپورٹ')} — ${_d(DateTime.now().millisecondsSinceEpoch)}\n');
    b.writeln('${Loc.t('Pieces', 'پیس')}: ${r.total.pieces}');
    if (money) b.writeln('${Loc.t('Cost', 'لاگت')}: ${instRs(r.total.cost)}');
    b.writeln('${Loc.t('Cash value', 'نقد مالیت')}: ${instRs(r.total.cash)}\n');
    for (final g in r.byCategory) {
      b.writeln('${g.name}: ${g.pieces}  ${instRs(money ? g.cost : g.cash)}');
    }
    b.writeln();
    for (final s in r.pieces) {
      b.writeln('${s.item.title.isEmpty ? s.item.model : s.item.title}  ${s.item.primaryId}  ${s.days}d');
    }
    return b.toString();
  }

  Future<void> _pdf(StockReport r, bool money) => InstPdf.shareTable(
        context,
        base: 'Stock_Report',
        title: Loc.t('Stock Report', 'اسٹاک رپورٹ'),
        sub: _d(DateTime.now().millisecondsSinceEpoch),
        summary: [
          (Loc.t('Pieces', 'پیس'), '${r.total.pieces}'),
          if (money) (Loc.t('Cost value', 'لاگت'), instRs(r.total.cost)),
          (Loc.t('Cash sale value', 'نقد قیمت پر'), instRs(r.total.cash)),
          for (final g in r.byCategory) (g.name, '${g.pieces}  •  ${instRs(money ? g.cost : g.cash)}'),
        ],
        headers: [
          Loc.t('Item', 'سامان'),
          Loc.t('Category', 'کیٹیگری'),
          'IMEI / Serial',
          Loc.t('Days', 'دن'),
          money ? Loc.t('Cost', 'لاگت') : Loc.t('Price', 'قیمت'),
        ],
        flex: const [4, 2, 4, 1, 2],
        right: const {3, 4},
        rows: [
          for (final s in r.pieces)
            [
              s.item.title.isEmpty ? s.item.model : s.item.title,
              s.category,
              s.item.idValues.values.where((v) => v.trim().isNotEmpty).join(' / '),
              '${s.days}',
              instRs(money ? s.item.costPrice : s.item.cashPrice),
            ]
        ],
      );

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final money = Session.isAdminOrManager;
    final r = _r;
    final pieces = r == null ? const <StockPiece>[] : r.pieces.where((s) => _age == null || stockAgeBucket(s.days) == _age).toList();
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Stock Report', 'اسٹاک رپورٹ'), Loc.t('Only pieces in stock', 'صرف اسٹاک والے پیس'), actions: [
          IconButton(
            tooltip: Loc.t('Share', 'شیئر'),
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            onPressed: r == null ? null : () => _share(context, _text(r, money)),
          ),
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
            onPressed: r == null ? null : () => _pdf(r, money),
          ),
        ]),
        Expanded(
          child: r == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
                  _card(p, [
                    _line(p, Loc.t('Pieces in stock', 'اسٹاک میں پیس'), '${r.total.pieces}', bold: true),
                    if (money) _line(p, Loc.t('Cost value', 'لاگت'), instRs(r.total.cost)),
                    _line(p, Loc.t('Cash sale value', 'نقد قیمت پر'), instRs(r.total.cash)),
                    if (money) _line(p, Loc.t('Margin in stock', 'اسٹاک میں منافع'), instRs(r.total.margin), c: r.total.margin >= 0 ? p.teal : p.red),
                  ]),
                  instSectionTitle(p, Loc.t('BY CATEGORY', 'کیٹیگری وار')),
                  _card(p, [
                    if (r.byCategory.isEmpty) Text('—', style: TextStyle(color: p.textMuted)),
                    for (final g in r.byCategory) _line(p, '${g.name} (${g.pieces})', instRs(money ? g.cost : g.cash)),
                  ]),
                  instSectionTitle(p, Loc.t('HOW OLD (DAYS IN STOCK)', 'کتنا پرانا (دن)')),
                  _card(p, [
                    for (var k = 0; k < r.byAge.length; k++)
                      _line(p, '${r.byAge[k].name} ${Loc.t('days', 'دن')} (${r.byAge[k].pieces})', instRs(money ? r.byAge[k].cost : r.byAge[k].cash),
                          c: k >= 2 && r.byAge[k].pieces > 0 ? p.red : null),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: [
                    ChoiceChip(label: Text(Loc.t('All', 'سب')), selected: _age == null, onSelected: (_) => setState(() => _age = null)),
                    for (var k = 0; k < stockAgeLabels.length; k++)
                      ChoiceChip(label: Text('${stockAgeLabels[k]} ${Loc.t('d', 'دن')}'), selected: _age == k, onSelected: (_) => setState(() => _age = k)),
                  ]),
                  instSectionTitle(p, Loc.t('PIECES (OLDEST FIRST)', 'پیس (پرانے پہلے)')),
                  if (pieces.isEmpty) _empty(p, Loc.t('Nothing here.', 'یہاں کچھ نہیں۔')),
                  for (final s in pieces)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: instCard(p),
                      child: ListTile(
                        title: Text(s.item.title.isEmpty ? s.item.model : s.item.title,
                            style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                        subtitle: Text([s.category, if (s.item.primaryId.isNotEmpty) s.item.primaryId, if (s.item.supplier.isNotEmpty) s.item.supplier].join('  •  '),
                            style: TextStyle(color: p.textMuted, fontSize: 12)),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(instRs(money ? s.item.costPrice : s.item.cashPrice), style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
                          Text('${s.days} ${Loc.t('days', 'دن')}',
                              style: TextStyle(color: stockAgeBucket(s.days) >= 2 ? p.red : p.textMuted, fontSize: 11.5)),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ===================================================================== due installments

class InstDueReportScreen extends StatefulWidget {
  const InstDueReportScreen({super.key});

  @override
  State<InstDueReportScreen> createState() => _InstDueReportScreenState();
}

class _InstDueReportScreenState extends State<InstDueReportScreen> {
  List<PlanView> _views = const [];
  int _from = 0;
  int _to = 0;
  String _label = '';
  bool _withLate = true;
  bool _loaded = false;

  Future<void> _load(int from, int to, String label) async {
    final views = await InstPlanRepository.instance.list();
    if (!mounted) return;
    setState(() {
      _views = views;
      _from = from;
      _to = to;
      _label = label;
      _loaded = true;
    });
  }

  String _text(List<DueEntry> list) {
    final b = StringBuffer('${Loc.t('Due Installments', 'آنے والی قسطیں')} — $_label\n');
    for (final e in list) {
      b.writeln('${_dShort(e.dueDate)}  ${e.customer} ${e.phone}  ${e.planNo} #${e.seq}  Rs ${e.remaining.round()}'
          '${e.daysLate > 0 ? '  (${e.daysLate} ${Loc.t('days late', 'دن لیٹ')})' : ''}');
    }
    b.writeln('\n${Loc.t('Total', 'کل')}: ${instRs(list.fold<double>(0, (a, e) => a + e.remaining))}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final today = dayStart(DateTime.now());
    final list = _loaded ? dueEntries(_views, from: _from, to: _to, today: today, withLate: _withLate) : const <DueEntry>[];
    final late = list.where((e) => e.daysLate > 0).fold<double>(0, (a, e) => a + e.remaining);
    final total = list.fold<double>(0, (a, e) => a + e.remaining);
    final days = dueByDay(list);
    final byDay = <int, List<DueEntry>>{};
    for (final e in list) {
      final d = DateTime.fromMillisecondsSinceEpoch(e.dueDate);
      byDay.putIfAbsent(DateTime(d.year, d.month, d.day).millisecondsSinceEpoch, () => []).add(e);
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Due Installments', 'آنے والی قسطیں'), _label, actions: [
          IconButton(
            tooltip: Loc.t('Share', 'شیئر'),
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            onPressed: list.isEmpty ? null : () => _share(context, _text(list)),
          ),
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
            onPressed: list.isEmpty
                ? null
                : () => InstPdf.shareTable(
                      context,
                      base: 'Due_Installments',
                      title: Loc.t('Due Installments', 'آنے والی قسطیں'),
                      sub: _label,
                      summary: [
                        (Loc.t('Installments', 'قسطیں'), '${list.length}'),
                        (Loc.t('Total to collect', 'کل وصولی'), instRs(total)),
                        if (late > 0.5) (Loc.t('of which late', 'اس میں لیٹ'), instRs(late)),
                      ],
                      headers: [
                        Loc.t('Date', 'تاریخ'),
                        Loc.t('Customer', 'کسٹمر'),
                        Loc.t('Phone', 'فون'),
                        Loc.t('Plan', 'پلان'),
                        Loc.t('Amount', 'رقم'),
                        Loc.t('Late', 'لیٹ'),
                      ],
                      flex: const [2, 3, 3, 2, 2, 1],
                      right: const {4, 5},
                      rows: [
                        for (final e in list)
                          [_dShort(e.dueDate), e.customer, e.phone, '${e.planNo} #${e.seq}', instRs(e.remaining), e.daysLate > 0 ? '${e.daysLate}' : '']
                      ],
                    ),
          ),
        ]),
        _RangeBar(future: true, onChanged: _load),
        SwitchListTile(
          dense: true,
          value: _withLate,
          onChanged: (v) => setState(() => _withLate = v),
          title: Text(Loc.t('Include older late installments', 'پرانی لیٹ قسطیں بھی'), style: TextStyle(color: p.textDark)),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                  _card(p, [
                    _line(p, Loc.t('Installments', 'قسطیں'), '${list.length}'),
                    _line(p, Loc.t('Total to collect', 'کل وصولی'), instRs(total), bold: true),
                    if (late > 0.5) _line(p, Loc.t('of which late', 'اس میں لیٹ'), instRs(late), c: p.red),
                  ]),
                  if (list.isEmpty) _empty(p, Loc.t('No installments in this period.', 'اس دوران کوئی قسط نہیں۔')),
                  for (final d in days) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                      child: Row(children: [
                        Text(_d(d.$1),
                            style: TextStyle(color: d.$1 < today ? p.red : p.textMuted, fontWeight: FontWeight.bold, fontSize: 12.5)),
                        const Spacer(),
                        Text('${d.$3} • ${instRs(d.$2)}', style: TextStyle(color: p.textMuted, fontWeight: FontWeight.bold, fontSize: 12.5)),
                      ]),
                    ),
                    for (final e in byDay[d.$1] ?? const <DueEntry>[])
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: instCard(p),
                        child: ListTile(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstPlanDetailScreen(planId: e.planId))),
                          title: Text(e.customer, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                          subtitle: Text([e.planNo, '#${e.seq}', e.item, e.phone].where((x) => x.isNotEmpty).join('  •  '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 12)),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(instRs(e.remaining), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                            if (e.daysLate > 0)
                              Text('${e.daysLate} ${Loc.t('days late', 'دن لیٹ')}', style: TextStyle(color: p.red, fontSize: 11.5)),
                          ]),
                        ),
                      ),
                  ],
                ]),
        ),
      ]),
    );
  }
}

// ===================================================================== receivable

class InstReceivableScreen extends StatefulWidget {
  const InstReceivableScreen({super.key});

  @override
  State<InstReceivableScreen> createState() => _InstReceivableScreenState();
}

class _InstReceivableScreenState extends State<InstReceivableScreen> {
  List<ReceivableRow> _rows = const [];
  bool _loaded = false;
  bool _onlyLate = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final views = await InstPlanRepository.instance.list();
    if (!mounted) return;
    setState(() {
      _rows = receivables(views);
      _loaded = true;
    });
  }

  String _text(List<ReceivableRow> list) {
    final b = StringBuffer('${Loc.t('Receivable', 'لینا ہے')} — ${_d(DateTime.now().millisecondsSinceEpoch)}\n');
    for (final r in list) {
      b.writeln('${r.name} ${r.phone}  Rs ${r.remaining.round()}'
          '${r.overdue > 0.5 ? '  (${Loc.t('late', 'لیٹ')} Rs ${r.overdue.round()}, ${r.daysLate} ${Loc.t('days', 'دن')})' : ''}');
    }
    b.writeln('\n${Loc.t('Total', 'کل')}: ${instRs(list.fold<double>(0, (a, r) => a + r.remaining))}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final q = _q.trim().toLowerCase();
    final list = _rows
        .where((r) => (!_onlyLate || r.overdue > 0.5) && (q.isEmpty || '${r.name} ${r.phone}'.toLowerCase().contains(q)))
        .toList();
    final total = list.fold<double>(0, (a, r) => a + r.remaining);
    final late = list.fold<double>(0, (a, r) => a + r.overdue);
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Receivable', 'لینا ہے'), Loc.t('Customer-wise balance', 'کسٹمر وار باقی'), actions: [
          IconButton(
            tooltip: Loc.t('Share', 'شیئر'),
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            onPressed: list.isEmpty ? null : () => _share(context, _text(list)),
          ),
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
            onPressed: list.isEmpty
                ? null
                : () => InstPdf.shareTable(
                      context,
                      base: 'Receivable',
                      title: Loc.t('Receivable', 'لینا ہے'),
                      sub: _d(DateTime.now().millisecondsSinceEpoch),
                      summary: [
                        (Loc.t('Customers', 'کسٹمرز'), '${list.length}'),
                        (Loc.t('Total receivable', 'کل لینا'), instRs(total)),
                        (Loc.t('Late', 'لیٹ'), instRs(late)),
                      ],
                      headers: [
                        Loc.t('Customer', 'کسٹمر'),
                        Loc.t('Phone', 'فون'),
                        Loc.t('Plans', 'پلان'),
                        Loc.t('Balance', 'باقی'),
                        Loc.t('Late', 'لیٹ'),
                        Loc.t('Days', 'دن'),
                      ],
                      flex: const [3, 3, 1, 2, 2, 1],
                      right: const {2, 3, 4, 5},
                      rows: [
                        for (final r in list)
                          [
                            r.name,
                            r.phone,
                            '${r.plans}',
                            instRs(r.remaining),
                            r.overdue > 0.5 ? instRs(r.overdue) : '',
                            r.daysLate > 0 ? '${r.daysLate}' : '',
                          ]
                      ],
                    ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: instDeco(p, Loc.t('Search name, phone', 'نام، فون سے تلاش'), suffix: const Icon(Icons.search)),
          ),
        ),
        SwitchListTile(
          dense: true,
          value: _onlyLate,
          onChanged: (v) => setState(() => _onlyLate = v),
          title: Text(Loc.t('Only late customers', 'صرف لیٹ کسٹمر'), style: TextStyle(color: p.textDark)),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                  _card(p, [
                    _line(p, Loc.t('Customers', 'کسٹمرز'), '${list.length}'),
                    _line(p, Loc.t('Total receivable', 'کل لینا'), instRs(total), bold: true),
                    _line(p, Loc.t('Late', 'لیٹ'), instRs(late), c: late > 0.5 ? p.red : p.textMuted),
                  ]),
                  const SizedBox(height: 10),
                  if (list.isEmpty) _empty(p, Loc.t('Nothing to collect.', 'کچھ لینا نہیں۔')),
                  for (final r in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: instCard(p),
                      child: ListTile(
                        onTap: () async {
                          await Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => InstCustomerDetailScreen(customerId: r.customerId)));
                          await _load();
                        },
                        title: Text(r.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          [
                            if (r.phone.isNotEmpty) r.phone,
                            Loc.t('${r.plans} plans', '${r.plans} پلان'),
                            if (r.nextDue > 0) '${Loc.t('next', 'اگلی')} ${_dShort(r.nextDue)}',
                          ].join('  •  '),
                          style: TextStyle(color: p.textMuted, fontSize: 12),
                        ),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(instRs(r.remaining), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                          if (r.overdue > 0.5)
                            Text('${Loc.t('late', 'لیٹ')} ${instRs(r.overdue)} • ${r.daysLate}${Loc.t('d', 'د')}',
                                style: TextStyle(color: p.red, fontSize: 11.5)),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ================================================================== Step 31: purchase history / returns history

/// Purchase history: muddat mein sab bill — supplier, pieces, raqam, ada, baqi. PDF / Excel.
class InstPurchaseReportScreen extends StatefulWidget {
  const InstPurchaseReportScreen({super.key});

  @override
  State<InstPurchaseReportScreen> createState() => _InstPurchaseReportScreenState();
}

class _InstPurchaseReportScreenState extends State<InstPurchaseReportScreen> {
  List<InstPurchase> _rows = const [];
  String _label = '';
  bool _loaded = false;

  Future<void> _load(int from, int to, String label) async {
    final rows = await InstPurchaseRepository.instance.purchases(from: from, to: to);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _label = label;
      _loaded = true;
    });
  }

  Future<void> _pdf() {
    final total = _rows.fold<double>(0, (a, x) => a + x.total);
    final due = _rows.fold<double>(0, (a, x) => a + x.due);
    return InstPdf.shareTable(
      context,
      base: 'Purchase_History',
      title: Loc.t('Purchase History', 'خریداری کی ہسٹری'),
      sub: _label,
      summary: [
        (Loc.t('Bills', 'بل'), '${_rows.length}  •  ${Loc.t('pieces', 'پیس')} ${_rows.fold<int>(0, (a, x) => a + x.itemCount)}'),
        (Loc.t('Total purchase', 'کل خریداری'), instRs(total)),
        (Loc.t('Still to pay', 'ابھی دینا ہے'), instRs(due)),
      ],
      headers: [Loc.t('Date', 'تاریخ'), Loc.t('Bill', 'بل'), Loc.t('Supplier', 'سپلائر'), Loc.t('Pieces', 'پیس'), Loc.t('Total', 'کل'), Loc.t('Due', 'باقی')],
      flex: const [2, 2, 4, 1, 2, 2],
      right: const {3, 4, 5},
      rows: [
        for (final r in _rows) [_dShort(r.purchaseDate), r.billNo, r.supplierName, '${r.itemCount}', instRs(r.total), instRs(r.due)]
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final total = _rows.fold<double>(0, (a, x) => a + x.total);
    final returned = _rows.fold<double>(0, (a, x) => a + x.returned);
    final due = _rows.fold<double>(0, (a, x) => a + x.due);
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Purchase History', 'خریداری کی ہسٹری'), _label, actions: [
          IconButton(
            tooltip: 'PDF / Excel',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
            onPressed: _rows.isEmpty ? null : _pdf,
          ),
        ]),
        _RangeBar(onChanged: _load),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 32), children: [
                  _card(p, [
                    _line(p, Loc.t('Bills', 'بل'), '${_rows.length}', bold: true),
                    _line(p, Loc.t('Pieces bought', 'خریدے پیس'), '${_rows.fold<int>(0, (a, x) => a + x.itemCount)}'),
                    _line(p, Loc.t('Total purchase', 'کل خریداری'), instRs(total)),
                    if (returned > 0) _line(p, Loc.t('Returned to suppliers', 'سپلائر کو واپس'), instRs(returned)),
                    _line(p, Loc.t('Still to pay', 'ابھی دینا ہے'), instRs(due), c: due > 0.5 ? p.red : p.teal, bold: true),
                  ]),
                  instSectionTitle(p, Loc.t('BILLS', 'بل')),
                  if (_rows.isEmpty) _empty(p, Loc.t('No purchase in this period.', 'اس دوران کوئی خریداری نہیں۔')),
                  for (final r in _rows)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: instCard(p),
                      child: ListTile(
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => InstPurchaseDetailScreen(purchaseId: r.id))),
                        leading: Icon(Icons.local_shipping_outlined, color: p.tealDark),
                        title: Text('${r.supplierName}  •  ${r.billNo}', style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${_dShort(r.purchaseDate)}  •  ${r.itemCount} ${Loc.t('pieces', 'پیس')}'
                          '${r.due > 0.5 ? '  •  ${Loc.t('due', 'باقی')} ${instRs(r.due)}' : ''}',
                          style: TextStyle(color: r.due > 0.5 ? p.red : p.textMuted, fontSize: 12),
                        ),
                        trailing: Text(instRs(r.total), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

/// Ek wapsi (returns history ki line).
class _ReturnRow {
  final int date;
  final String type; // sale / plan / purchase
  final String party;
  final String item;
  final double amount;
  final Widget? open;
  const _ReturnRow(this.date, this.type, this.party, this.item, this.amount, this.open);
}

/// Returns history: naqd sale wapsi (refund), qist ka saman wapas, supplier ko wapsi — tareekh war. PDF / Excel.
class InstReturnsReportScreen extends StatefulWidget {
  const InstReturnsReportScreen({super.key});

  @override
  State<InstReturnsReportScreen> createState() => _InstReturnsReportScreenState();
}

class _InstReturnsReportScreenState extends State<InstReturnsReportScreen> {
  List<_ReturnRow> _rows = const [];
  String _label = '';
  bool _loaded = false;

  String _typeLabel(String t) => switch (t) {
        'sale' => Loc.t('Sale return', 'سیل واپسی'),
        'plan' => Loc.t('Qist item back', 'قسط سامان واپس'),
        _ => Loc.t('Purchase return', 'خریداری واپسی'),
      };

  Future<void> _load(int from, int to, String label) async {
    bool inRange(int t) => t >= from && t < to;
    final out = <_ReturnRow>[];
    for (final v in await InstCashSaleRepository.instance.list()) {
      final at = v.sale.returnedAt;
      if (at != null && inRange(at)) {
        out.add(_ReturnRow(at, 'sale', v.sale.customerName, v.itemTitle, v.sale.refund, InstCashSaleDetailScreen(saleId: v.sale.id)));
      }
    }
    for (final v in await InstPlanRepository.instance.list()) {
      if (v.plan.status == planRepossessed && inRange(v.plan.closedAt)) {
        out.add(_ReturnRow(v.plan.closedAt, 'plan', v.customerName, v.itemTitle, v.status.remaining, InstPlanDetailScreen(planId: v.plan.id)));
      }
    }
    if (Session.isAdminOrManager) {
      final names = {for (final s in await InstPurchaseRepository.instance.suppliers()) s.supplier.id: s.supplier.name};
      for (final r in await InstPurchaseRepository.instance.returns()) {
        if (inRange(r.returnedAt)) {
          out.add(_ReturnRow(r.returnedAt, 'purchase', names[r.supplierId] ?? '', [r.itemTitle, r.itemCode].where((x) => x.isNotEmpty).join(' '),
              r.amount, r.purchaseId == null ? null : InstPurchaseDetailScreen(purchaseId: r.purchaseId!)));
        }
      }
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    if (!mounted) return;
    setState(() {
      _rows = out;
      _label = label;
      _loaded = true;
    });
  }

  double _sum(String t) => _rows.where((r) => r.type == t).fold<double>(0, (a, r) => a + r.amount);

  Future<void> _pdf() => InstPdf.shareTable(
        context,
        base: 'Returns_History',
        title: Loc.t('Returns History', 'واپسی کی ہسٹری'),
        sub: _label,
        summary: [
          (Loc.t('Sale returns (refund)', 'سیل واپسی (واپس کیا)'), instRs(_sum('sale'))),
          (Loc.t('Qist items back (remaining then)', 'قسط سامان واپس (اس وقت باقی)'), instRs(_sum('plan'))),
          if (Session.isAdminOrManager) (Loc.t('Purchase returns', 'خریداری واپسی'), instRs(_sum('purchase'))),
        ],
        headers: [Loc.t('Date', 'تاریخ'), Loc.t('Type', 'قسم'), Loc.t('Party', 'فریق'), Loc.t('Item', 'سامان'), Loc.t('Amount', 'رقم')],
        flex: const [2, 3, 3, 4, 2],
        right: const {4},
        rows: [for (final r in _rows) [_dShort(r.date), _typeLabel(r.type), r.party, r.item, instRs(r.amount)]],
      );

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Returns History', 'واپسی کی ہسٹری'), _label, actions: [
          IconButton(
            tooltip: 'PDF / Excel',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
            onPressed: _rows.isEmpty ? null : _pdf,
          ),
        ]),
        _RangeBar(onChanged: _load),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 32), children: [
                  _card(p, [
                    _line(p, Loc.t('Sale returns (refund)', 'سیل واپسی (واپس کیا)'), instRs(_sum('sale'))),
                    _line(p, Loc.t('Qist items back (remaining then)', 'قسط سامان واپس (اس وقت باقی)'), instRs(_sum('plan'))),
                    if (Session.isAdminOrManager) _line(p, Loc.t('Purchase returns', 'خریداری واپسی'), instRs(_sum('purchase'))),
                  ]),
                  instSectionTitle(p, Loc.t('RETURNS', 'واپسیاں')),
                  if (_rows.isEmpty) _empty(p, Loc.t('No return in this period.', 'اس دوران کوئی واپسی نہیں۔')),
                  for (final r in _rows)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: instCard(p),
                      child: ListTile(
                        onTap: r.open == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => r.open!)),
                        leading: Icon(
                          r.type == 'purchase' ? Icons.keyboard_return : (r.type == 'plan' ? Icons.undo : Icons.assignment_return_outlined),
                          color: r.type == 'purchase' ? p.navy : p.orange,
                        ),
                        title: Text('${_typeLabel(r.type)}  •  ${r.party}', style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                        subtitle: Text('${_dShort(r.date)}  •  ${r.item}', style: TextStyle(color: p.textMuted, fontSize: 12)),
                        trailing: Text(instRs(r.amount), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}
