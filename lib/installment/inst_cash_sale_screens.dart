import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_cash_sale_repository.dart';
import 'inst_models.dart';
import 'inst_plan_math.dart';
import 'inst_repository.dart';
import 'inst_ui.dart';

/// Naqd (cash) sale: list, nayi sale (stock se piece), raseed / wapas.

String _dt(int ms) => DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));

// ===================================================================== list

class InstCashSalesScreen extends StatefulWidget {
  const InstCashSalesScreen({super.key});

  @override
  State<InstCashSalesScreen> createState() => _InstCashSalesScreenState();
}

class _InstCashSalesScreenState extends State<InstCashSalesScreen> {
  List<CashSaleView> _all = const [];
  bool _loaded = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await InstCashSaleRepository.instance.list();
    if (!mounted) return;
    setState(() {
      _all = l;
      _loaded = true;
    });
  }

  Future<void> _open(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final q = _q.trim().toLowerCase();
    final list = _all
        .where((v) =>
            q.isEmpty ||
            '${v.sale.saleNo} ${v.sale.customerName} ${v.sale.phone} ${v.itemTitle}'.toLowerCase().contains(q) ||
            (v.item?.matches(q) ?? false))
        .toList();
    final today = dayStart(DateTime.now());
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1).millisecondsSinceEpoch;
    final todayTotal = _all.where((v) => v.sale.soldAt >= today).fold<double>(0, (a, v) => a + v.sale.price);
    final monthTotal = _all.where((v) => v.sale.soldAt >= monthStart).fold<double>(0, (a, v) => a + v.sale.price);
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.teal,
        foregroundColor: Colors.white,
        onPressed: () => _open(const InstNewCashSaleScreen()),
        icon: const Icon(Icons.point_of_sale),
        label: Text(Loc.t('New Cash Sale', 'نئی نقد سیل')),
      ),
      body: Column(children: [
        instHeader(context, p, Loc.t('Cash Sales', 'نقد سیل'), Loc.t('Pieces sold without installments', 'بغیر قسط بکے پیس')),
        if (_loaded)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            padding: const EdgeInsets.all(14),
            decoration: instCard(p),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Loc.t('Today', 'آج'), style: TextStyle(color: p.textMuted, fontSize: 12)),
                  Text(instRs(todayTotal), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 17)),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(Loc.t('This month', 'اس مہینے'), style: TextStyle(color: p.textMuted, fontSize: 12)),
                  Text(instRs(monthTotal), style: TextStyle(color: p.teal, fontWeight: FontWeight.bold, fontSize: 17)),
                ]),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: instDeco(p, Loc.t('Search sale no., customer, IMEI', 'سیل نمبر، کسٹمر، IMEI سے تلاش'), suffix: const Icon(Icons.search)),
          ),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _all.isEmpty
                              ? Loc.t('No cash sales yet. Tap "New Cash Sale".', 'ابھی کوئی نقد سیل نہیں۔ "نئی نقد سیل" دبائیں۔')
                              : Loc.t('Nothing found.', 'کچھ نہیں ملا۔'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.textMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final v = list[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: instCard(p),
                          child: ListTile(
                            onTap: () => _open(InstCashSaleDetailScreen(saleId: v.sale.id)),
                            title: Text(v.itemTitle.isEmpty ? v.sale.saleNo : v.itemTitle,
                                style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              [v.sale.saleNo, _dt(v.sale.soldAt), if (v.sale.customerName.isNotEmpty) v.sale.customerName].join('  •  '),
                              style: TextStyle(color: p.textMuted, fontSize: 12),
                            ),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(instRs(v.sale.price),
                                  style: TextStyle(
                                      color: v.sale.isReturned ? p.textMuted : p.teal,
                                      fontWeight: FontWeight.bold,
                                      decoration: v.sale.isReturned ? TextDecoration.lineThrough : null)),
                              if (v.sale.isReturned)
                                Text(Loc.t('Returned', 'واپس'), style: TextStyle(color: p.red, fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ===================================================================== new sale

class InstNewCashSaleScreen extends StatefulWidget {
  /// Stock / item form se: yahi piece pehle se chuna hua.
  final int? itemId;
  const InstNewCashSaleScreen({super.key, this.itemId});

  @override
  State<InstNewCashSaleScreen> createState() => _InstNewCashSaleScreenState();
}

class _InstNewCashSaleScreenState extends State<InstNewCashSaleScreen> {
  List<InstItem> _stock = const [];
  Map<int, String> _cats = const {};
  InstItem? _item;
  final _price = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  String _method = 'cash';
  int? _customerId;
  String _q = '';
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_price, _name, _phone, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final items = await InstRepository.instance.items(status: itemInStock);
    final cats = await InstRepository.instance.categories();
    if (!mounted) return;
    setState(() {
      _stock = items;
      _cats = {for (final c in cats) if (c.id != null) c.id!: c.name};
      _loaded = true;
      if (widget.itemId != null) {
        for (final i in items) {
          if (i.id == widget.itemId) _choose(i);
        }
      }
    });
  }

  void _choose(InstItem i) {
    _item = i;
    _price.text = i.cashPrice > 0 ? instPlain(i.cashPrice) : '';
  }

  Future<void> _save() async {
    final it = _item;
    if (it == null || _saving) return;
    setState(() => _saving = true);
    try {
      final id = await InstCashSaleRepository.instance.sell(
        itemId: it.id!,
        price: instParse(_price.text),
        customerId: _customerId,
        customerName: _name.text,
        phone: _phone.text,
        method: _method,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InstCashSaleDetailScreen(saleId: id)));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        instToast(context, instErr(e));
      }
    }
  }

  /// Customers list se chunein (naam / phone bhar jata hai; customer ke page par yeh khareedari dikhti hai).
  Future<void> _pickCustomer() async {
    final all = await InstRepository.instance.listCustomers();
    if (!mounted) return;
    final p = ThemeManager.palette;
    var q = '';
    final picked = await showDialog<InstCustomerRow>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final t = q.trim().toLowerCase();
          final list = all.where((c) => t.isEmpty || '${c.name} ${c.phone}'.toLowerCase().contains(t)).take(60).toList();
          return AlertDialog(
            title: Text(Loc.t('Choose customer', 'کسٹمر چنیں')),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(children: [
                TextField(
                  autofocus: true,
                  onChanged: (v) => setD(() => q = v),
                  decoration: instDeco(p, Loc.t('Search name, phone', 'نام، فون سے تلاش'), suffix: const Icon(Icons.search)),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(children: [
                    for (final c in list)
                      ListTile(
                        dense: true,
                        title: Text(c.name),
                        subtitle: c.phone.isEmpty ? null : Text(c.phone),
                        onTap: () => Navigator.pop(ctx, c),
                      ),
                  ]),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Loc.t('Cancel', 'منسوخ')))],
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customerId = picked.id;
      _name.text = picked.name;
      _phone.text = picked.phone;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    Widget gap() => const SizedBox(height: 12);
    final it = _item;
    final price = instParse(_price.text);
    final money = Session.isAdminOrManager;
    final list = _stock.where((i) => i.matches(_q)).toList();
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('New Cash Sale', 'نئی نقد سیل'), Loc.t('Full payment now, no installments', 'پوری رقم ابھی، کوئی قسط نہیں')),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : it == null
                  ? Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: TextField(
                          autofocus: true,
                          onChanged: (v) => setState(() => _q = v),
                          decoration: instDeco(p, Loc.t('Find piece: model, IMEI, serial', 'پیس تلاش: ماڈل، IMEI، سیریل'),
                              suffix: const Icon(Icons.search)),
                        ),
                      ),
                      Expanded(
                        child: list.isEmpty
                            ? Center(
                                child: Text(
                                    _stock.isEmpty ? Loc.t('Stock is empty.', 'اسٹاک خالی ہے۔') : Loc.t('Nothing found.', 'کچھ نہیں ملا۔'),
                                    style: TextStyle(color: p.textMuted)))
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                                itemCount: list.length,
                                itemBuilder: (_, i) {
                                  final s = list[i];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: instCard(p),
                                    child: ListTile(
                                      onTap: () => setState(() => _choose(s)),
                                      title: Text(s.title.isEmpty ? s.model : s.title,
                                          style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                                      subtitle: Text(
                                          [_cats[s.categoryId] ?? '', if (s.color.isNotEmpty) s.color, if (s.primaryId.isNotEmpty) s.primaryId]
                                              .where((x) => x.isNotEmpty)
                                              .join('  •  '),
                                          style: TextStyle(color: p.textMuted, fontSize: 12)),
                                      trailing: Text(instRs(s.cashPrice), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ])
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                      instSectionTitle(p, Loc.t('PIECE', 'پیس')),
                      Container(
                        decoration: instCard(p),
                        child: ListTile(
                          title: Text(it.title.isEmpty ? it.model : it.title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              [_cats[it.categoryId] ?? '', if (it.color.isNotEmpty) it.color, if (it.primaryId.isNotEmpty) it.primaryId]
                                  .where((x) => x.isNotEmpty)
                                  .join('  •  '),
                              style: TextStyle(color: p.textMuted, fontSize: 12)),
                          trailing: TextButton(
                            onPressed: () => setState(() => _item = null),
                            child: Text(Loc.t('Change', 'بدلیں')),
                          ),
                        ),
                      ),
                      instSectionTitle(p, Loc.t('PRICE', 'قیمت')),
                      TextField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        decoration: instDeco(p, Loc.t('Sale price *', 'قیمت فروخت *')),
                      ),
                      if (kShowProfitOutsideReports && money && it.costPrice > 0 && price > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                          child: Text(
                            '${Loc.t('Profit', 'منافع')}: ${instRs(price - it.costPrice)}  (${Loc.t('cost', 'لاگت')} ${instRs(it.costPrice)})',
                            style: TextStyle(color: price >= it.costPrice ? p.teal : p.red, fontWeight: FontWeight.bold),
                          ),
                        ),
                      gap(),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'cash', label: Text(Loc.t('Cash', 'کیش')), icon: const Icon(Icons.payments_outlined)),
                          ButtonSegment(value: 'bank', label: Text(Loc.t('Bank', 'بینک')), icon: const Icon(Icons.account_balance_outlined)),
                        ],
                        selected: {_method},
                        onSelectionChanged: (s) => setState(() => _method = s.first),
                      ),
                      instSectionTitle(p, Loc.t('CUSTOMER (OPTIONAL)', 'کسٹمر (اختیاری)')),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickCustomer,
                            icon: Icon(_customerId == null ? Icons.person_search_outlined : Icons.how_to_reg, color: p.teal),
                            label: Text(_customerId == null
                                ? Loc.t('From customer list', 'کسٹمر لسٹ سے')
                                : Loc.t('Linked to customer', 'کسٹمر سے جڑا ہوا')),
                          ),
                        ),
                        if (_customerId != null)
                          IconButton(
                            tooltip: Loc.t('Unlink', 'الگ کریں'),
                            icon: Icon(Icons.link_off, color: p.textMuted),
                            onPressed: () => setState(() => _customerId = null),
                          ),
                      ]),
                      gap(),
                      TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: instDeco(p, Loc.t('Name', 'نام'))),
                      gap(),
                      TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: instDeco(p, Loc.t('Phone', 'فون'))),
                      gap(),
                      TextField(controller: _note, maxLines: 2, decoration: instDeco(p, Loc.t('Note', 'نوٹ'))),
                      const SizedBox(height: 20),
                      instPrimaryButton(
                        p,
                        _saving ? Loc.t('Saving...', 'محفوظ ہو رہا ہے...') : '${Loc.t('Sell for', 'بیچیں')} ${instRs(price)}',
                        _saving || price <= 0 ? null : _save,
                        icon: Icons.point_of_sale,
                      ),
                    ]),
        ),
      ]),
    );
  }
}

// ===================================================================== detail

class InstCashSaleDetailScreen extends StatefulWidget {
  final int saleId;
  const InstCashSaleDetailScreen({super.key, required this.saleId});

  @override
  State<InstCashSaleDetailScreen> createState() => _InstCashSaleDetailScreenState();
}

class _InstCashSaleDetailScreenState extends State<InstCashSaleDetailScreen> {
  CashSaleView? _v;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await InstCashSaleRepository.instance.view(widget.saleId);
    if (!mounted) return;
    setState(() {
      _v = v;
      _loaded = true;
    });
  }

  Future<void> _share() async {
    final v = _v;
    if (v == null) return;
    try {
      await Share.share(cashSaleReceipt(v));
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  /// Customer ne saman wapas kiya: kitne paise wapas diye (pehle se poori qeemat), wajah.
  Future<void> _return() async {
    final v = _v;
    if (v == null) return;
    final p = ThemeManager.palette;
    final amount = TextEditingController(text: instPlain(v.sale.price));
    final note = TextEditingController();
    var method = v.sale.method;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final refund = instParse(amount.text);
          return AlertDialog(
            title: Text(Loc.t('Sale return', 'سیل واپسی')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${v.sale.saleNo} • ${v.itemTitle} • ${instRs(v.sale.price)}', style: TextStyle(color: p.textMuted)),
                const SizedBox(height: 6),
                Text(Loc.t('The piece goes back into stock.', 'پیس دوبارہ اسٹاک میں جائے گا۔'), style: TextStyle(color: p.teal)),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (_) => setD(() {}),
                  decoration: instDeco(p, Loc.t('Money given back to customer', 'کسٹمر کو واپس دی گئی رقم')),
                ),
                if (refund < v.sale.price - 0.5)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${Loc.t('Deduction kept by shop', 'دکان نے کاٹے')}: ${instRs(v.sale.price - refund)}',
                        style: TextStyle(color: p.teal, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'cash', label: Text(Loc.t('Cash', 'کیش'))),
                    ButtonSegment(value: 'bank', label: Text(Loc.t('Bank', 'بینک'))),
                  ],
                  selected: {method},
                  onSelectionChanged: (x) => setD(() => method = x.first),
                ),
                const SizedBox(height: 12),
                TextField(controller: note, decoration: instDeco(p, Loc.t('Reason', 'وجہ'))),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Return', 'واپس لیں'))),
            ],
          );
        },
      ),
    );
    // Controllers dispose nahi kiye: dialog ki band hone wali animation abhi unhein istemal kar rahi hoti hai.
    if (ok != true) return;
    try {
      await InstCashSaleRepository.instance.returnSale(v.sale, refund: instParse(amount.text), note: note.text, method: method);
      await _load();
      if (mounted) instToast(context, Loc.t('Returned. Piece is back in stock.', 'واپس ہو گیا۔ پیس اسٹاک میں آ گیا۔'));
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _cancel() async {
    final v = _v;
    if (v == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('Delete this wrong entry?', 'یہ غلط اندراج حذف کریں؟')),
        content: Text(Loc.t(
            '${v.sale.saleNo}: only for a mistake — the sale disappears, the piece goes back to stock and its cash entries are removed. For a real customer return use "Sale return".',
            '${v.sale.saleNo}: صرف غلطی کے لیے — سیل ختم، پیس اسٹاک میں، کیش کے اندراج ہٹ جائیں گے۔ اصل واپسی کے لیے "سیل واپسی" استعمال کریں۔')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('No', 'نہیں'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Yes, cancel', 'ہاں، واپس'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await InstCashSaleRepository.instance.cancel(v.sale);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final v = _v;
    final money = Session.isAdminOrManager;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, v == null ? Loc.t('Cash Sale', 'نقد سیل') : v.sale.saleNo, v?.itemTitle ?? '', actions: [
          if (v != null && money)
            IconButton(
                tooltip: Loc.t('Delete wrong entry', 'غلط اندراج حذف'),
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                onPressed: _cancel),
        ]),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : v == null
                  ? Center(child: Text(Loc.t('Sale not found.', 'سیل نہیں ملی۔'), style: TextStyle(color: p.textMuted)))
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: instCard(p),
                        child: Column(children: [
                          Row(children: [
                            Icon(Icons.check_circle, color: p.teal),
                            const SizedBox(width: 8),
                            Text(Loc.t('Paid in full', 'پوری رقم ادا'), style: TextStyle(color: p.teal, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(instRs(v.sale.price), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 20)),
                          ]),
                          const SizedBox(height: 8),
                          instInfoLine(p, Loc.t('Date', 'تاریخ'), _dt(v.sale.soldAt)),
                          instInfoLine(p, Loc.t('Item', 'سامان'), v.itemTitle),
                          for (final e in (v.item?.idValues ?? const <String, String>{}).entries) instInfoLine(p, e.key, e.value),
                          instInfoLine(p, Loc.t('Customer', 'کسٹمر'), v.sale.customerName),
                          instInfoLine(p, Loc.t('Phone', 'فون'), v.sale.phone),
                          instInfoLine(p, Loc.t('Paid by', 'ادائیگی'), v.sale.method == 'bank' ? Loc.t('Bank', 'بینک') : Loc.t('Cash', 'کیش')),
                          if (kShowProfitOutsideReports && money && v.sale.hasCost) ...[
                            instInfoLine(p, Loc.t('Cost', 'لاگت'), instRs(v.sale.costPrice)),
                            instInfoLine(p, Loc.t('Profit', 'منافع'), instRs(v.sale.profit)),
                          ],
                          instInfoLine(p, Loc.t('Note', 'نوٹ'), v.sale.note),
                          instInfoLine(p, Loc.t('Sold by', 'فروخت کنندہ'), v.sale.soldBy),
                        ]),
                      ),
                      if (v.sale.isReturned) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: instCard(p),
                          child: Column(children: [
                            Row(children: [
                              Icon(Icons.assignment_return_outlined, color: p.red),
                              const SizedBox(width: 8),
                              Text(Loc.t('Returned by customer', 'کسٹمر نے واپس کیا'), style: TextStyle(color: p.red, fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 6),
                            instInfoLine(p, Loc.t('Date', 'تاریخ'), _dt(v.sale.returnedAt!)),
                            instInfoLine(p, Loc.t('Money given back', 'واپس دی رقم'), instRs(v.sale.refund)),
                            instInfoLine(p, Loc.t('Kept by shop', 'دکان کے پاس رہا'), instRs(v.sale.kept)),
                            instInfoLine(p, Loc.t('Reason', 'وجہ'), v.sale.returnNote),
                          ]),
                        ),
                      ] else if (money) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: p.red),
                          onPressed: _return,
                          icon: const Icon(Icons.assignment_return_outlined),
                          label: Text(Loc.t('Sale return (customer gave it back)', 'سیل واپسی (کسٹمر نے واپس کیا)')),
                        ),
                      ],
                      const SizedBox(height: 14),
                      instPrimaryButton(p, Loc.t('Share receipt (WhatsApp)', 'رسید بھیجیں (واٹس ایپ)'), _share, icon: Icons.share_outlined),
                    ]),
        ),
      ]),
    );
  }
}
