import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_items_screen.dart';
import 'inst_models.dart';
import 'inst_pdf.dart';
import 'inst_purchase_repository.dart';
import 'inst_repository.dart';
import 'inst_scan.dart';
import 'inst_ui.dart';

/// Khareed (purchase): bill list, naya bill (kai pieces), bill ki tafseel, suppliers aur un ka khata.
/// Sirf Admin / Manager (home tile bhi sirf unhein dikhti hai).

String _date(int ms) => ms <= 0 ? '—' : DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));

final _money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

// ===================================================================== bill list

class InstPurchasesScreen extends StatefulWidget {
  const InstPurchasesScreen({super.key});

  @override
  State<InstPurchasesScreen> createState() => _InstPurchasesScreenState();
}

class _InstPurchasesScreenState extends State<InstPurchasesScreen> {
  List<InstPurchase> _all = const [];
  PurchaseSummary _month = const PurchaseSummary();
  bool _loaded = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    InstRepository.instance.changes.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    InstRepository.instance.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final repo = InstPurchaseRepository.instance;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    final to = DateTime(now.year, now.month + 1, 1).millisecondsSinceEpoch;
    final list = await repo.purchases();
    final sum = await repo.summary(from: from, to: to);
    if (!mounted) return;
    setState(() {
      _all = list;
      _month = sum;
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
    final list = q.isEmpty
        ? _all
        : _all.where((b) => '${b.billNo} ${b.supplierName} ${b.note}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: Session.isAdminOrManager
          ? FloatingActionButton.extended(
              backgroundColor: p.teal,
              foregroundColor: Colors.white,
              onPressed: () => _open(const InstNewPurchaseScreen()),
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(Loc.t('New Purchase', 'نئی خریداری')),
            )
          : null,
      body: Column(children: [
        instHeader(context, p, Loc.t('Purchases', 'خریداری'), Loc.t('Bills from suppliers', 'سپلائرز کے بل'), actions: [
          IconButton(
            tooltip: Loc.t('Suppliers', 'سپلائرز'),
            icon: const Icon(Icons.local_shipping_outlined, color: Colors.white),
            onPressed: () => _open(const InstSuppliersScreen()),
          ),
        ]),
        if (_loaded)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            padding: const EdgeInsets.all(14),
            decoration: instCard(p),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Loc.t('This month', 'اس مہینے'), style: TextStyle(color: p.textMuted, fontSize: 12)),
                  Text(instRs(_month.total), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 17)),
                  Text(Loc.t('${_month.bills} bills • ${_month.pieces} pieces', '${_month.bills} بل • ${_month.pieces} پیس'),
                      style: TextStyle(color: p.textMuted, fontSize: 11.5)),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(Loc.t('To pay suppliers', 'سپلائرز کو دینا'), style: TextStyle(color: p.textMuted, fontSize: 12)),
                  Text(instRs(_month.payable),
                      style: TextStyle(color: _month.payable > 0.5 ? p.red : p.teal, fontWeight: FontWeight.bold, fontSize: 17)),
                  Text('${Loc.t('Paid this month', 'اس مہینے ادا')} ${instRs(_month.paid)}',
                      style: TextStyle(color: p.textMuted, fontSize: 11.5)),
                ]),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: instDeco(p, Loc.t('Search bill no., supplier', 'بل نمبر، سپلائر سے تلاش'), suffix: const Icon(Icons.search)),
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
                              ? Loc.t('No purchases yet. Tap "New Purchase".', 'ابھی کوئی خریداری نہیں۔ "نئی خریداری" دبائیں۔')
                              : Loc.t('Nothing found.', 'کچھ نہیں ملا۔'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.textMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _billTile(p, list[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _billTile(AppPalette p, InstPurchase b) {
    final due = b.due;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(InstPurchaseDetailScreen(purchaseId: b.id)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: instCard(p),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.supplierName.isEmpty ? '—' : b.supplierName,
                  style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15.5)),
              Text('${b.billNo}  •  ${_date(b.purchaseDate)}  •  ${Loc.t('${b.itemCount} pcs', '${b.itemCount} پیس')}',
                  style: TextStyle(color: p.textMuted, fontSize: 12)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(instRs(b.total), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
            Text(
              due > 0.5 ? '${Loc.t('Due', 'باقی')} ${instRs(due)}' : Loc.t('Paid', 'ادا شدہ'),
              style: TextStyle(color: due > 0.5 ? p.red : p.teal, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ===================================================================== new bill

class InstNewPurchaseScreen extends StatefulWidget {
  final int? supplierId;
  const InstNewPurchaseScreen({super.key, this.supplierId});

  @override
  State<InstNewPurchaseScreen> createState() => _InstNewPurchaseScreenState();
}

class _InstNewPurchaseScreenState extends State<InstNewPurchaseScreen> {
  List<InstSupplierRow> _suppliers = const [];
  List<InstCategory> _cats = const [];
  late int? _supplierId = widget.supplierId;
  final _billNo = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  int _day = DateTime.now().millisecondsSinceEpoch;
  String _method = 'cash';
  final List<InstItem> _items = [];
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _billNo.dispose();
    _paid.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await InstPurchaseRepository.instance.suppliers();
    final c = await InstRepository.instance.categories();
    if (!mounted) return;
    setState(() {
      _suppliers = s;
      _cats = c;
      _loaded = true;
      if (_supplierId != null && !s.any((r) => r.supplier.id == _supplierId)) _supplierId = null;
    });
  }

  double get _total => _items.fold<double>(0, (a, i) => a + i.costPrice);

  Future<void> _newSupplier() async {
    final id = await showSupplierDialog(context);
    if (id == null) return;
    await _load();
    if (mounted) setState(() => _supplierId = id);
  }

  Future<void> _addPiece({InstItem? template, int? replaceAt}) async {
    if (_cats.isEmpty) return instToast(context, Loc.t('Add a category first.', 'پہلے کیٹیگری بنائیں۔'));
    final it = await Navigator.of(context).push<InstItem>(MaterialPageRoute(
        builder: (_) => InstItemFormScreen(
              categories: _cats,
              draft: true,
              template: template,
              initialCategoryId: template?.categoryId ?? (_items.isEmpty ? null : _items.last.categoryId),
            )));
    if (it == null || !mounted) return;
    setState(() {
      if (replaceAt != null) {
        _items[replaceAt] = it;
      } else {
        _items.add(it);
      }
    });
  }

  /// Pichle piece jaisa naya (model / qeemat wahi, IMEI khali).
  Future<void> _copy(InstItem it) => _addPiece(template: it.copyWith(idValues: const {}));

  /// Ek hi model ke kai pieces (Step 30): model / rang / qeemat aakhri piece wali, sirf har dabbe ka IMEI scan karte
  /// jao — har scan par ek piece list mein. Wapas aane par ruk jata hai. IMEI pehle se list / stock mein ho to chhor.
  Future<void> _scanMany() async {
    if (_items.isEmpty) return;
    final last = _items.last;
    final cat = _cats.where((c) => c.id == last.categoryId).firstOrNull;
    final field = cat != null && cat.idFields.isNotEmpty
        ? cat.idFields.first
        : (last.idValues.keys.isNotEmpty ? last.idValues.keys.first : 'IMEI 1');
    final imei = field.toLowerCase().contains('imei');
    var added = 0;
    while (mounted) {
      final have = {for (final it in _items) ...it.idValues.values.map(normalizeIdValue)};
      final code = await Navigator.of(context).push<String>(MaterialPageRoute(
          builder: (_) => InstBarcodeScanPage(
              accept: (v) =>
                  (imei ? RegExp(r'^\d{15}$').hasMatch(v.trim()) : v.trim().length >= 4) && !have.contains(normalizeIdValue(v)))));
      if (code == null || !mounted) break;
      setState(() => _items.add(last.copyWith(idValues: {field: code.trim()})));
      added++;
      instToast(context, Loc.t('Added ${_items.length} — scan the next box', '${_items.length} شامل — اگلا ڈبہ اسکین کریں'));
    }
    if (added > 0 && mounted) instToast(context, Loc.t('$added pieces added', '$added پیس شامل ہوئے'));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: DateTime.fromMillisecondsSinceEpoch(_day), firstDate: DateTime(2015), lastDate: now);
    if (d != null) setState(() => _day = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch);
  }

  Future<void> _save() async {
    if (_saving) return;
    final sid = _supplierId;
    if (sid == null) return instToast(context, Loc.t('Choose a supplier.', 'سپلائر چنیں۔'));
    if (_items.isEmpty) return instToast(context, Loc.t('Add at least one piece.', 'کم از کم ایک پیس شامل کریں۔'));
    setState(() => _saving = true);
    try {
      final id = await InstPurchaseRepository.instance.createPurchase(
        supplierId: sid,
        items: List.of(_items),
        billNo: _billNo.text,
        purchaseDate: _day,
        note: _note.text,
        paidNow: instParse(_paid.text),
        method: _method,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InstPurchaseDetailScreen(purchaseId: id)));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        instToast(context, instErr(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    Widget gap() => const SizedBox(height: 12);
    final catName = {for (final c in _cats) c.id: c.name};
    final total = _total;
    final paid = instParse(_paid.text);
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('New Purchase', 'نئی خریداری'), Loc.t('All pieces go into stock', 'سب پیس اسٹاک میں جائیں گے')),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                  instSectionTitle(p, Loc.t('SUPPLIER', 'سپلائر')),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _supplierId,
                        isExpanded: true,
                        decoration: instDeco(p, Loc.t('Supplier *', 'سپلائر *')),
                        items: [
                          for (final r in _suppliers)
                            DropdownMenuItem(value: r.supplier.id, child: Text(r.supplier.name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => _supplierId = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: Loc.t('New supplier', 'نیا سپلائر'),
                      onPressed: _newSupplier,
                      icon: const Icon(Icons.person_add_alt),
                    ),
                  ]),
                  gap(),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _billNo,
                        decoration: instDeco(p, Loc.t('Bill no.', 'بل نمبر'), hint: Loc.t('Auto if empty', 'خالی ہو تو خود')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: instDeco(p, Loc.t('Date', 'تاریخ'), suffix: const Icon(Icons.event)),
                          child: Text(DateFormat('dd MMM yy').format(DateTime.fromMillisecondsSinceEpoch(_day)),
                              style: TextStyle(color: p.textDark, fontSize: 15)),
                        ),
                      ),
                    ),
                  ]),
                  instSectionTitle(p, Loc.t('PIECES (${_items.length})', 'پیس (${_items.length})')),
                  for (var i = 0; i < _items.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: instCard(p),
                      child: ListTile(
                        onTap: () => _addPiece(template: _items[i], replaceAt: i),
                        title: Text(_items[i].title.isEmpty ? _items[i].model : _items[i].title,
                            style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          [
                            catName[_items[i].categoryId] ?? '',
                            if (_items[i].primaryId.isNotEmpty) _items[i].primaryId,
                            '${Loc.t('Cost', 'لاگت')} ${instRs(_items[i].costPrice)}',
                            if (_items[i].cashPrice > 0) '${Loc.t('Cash', 'نقد')} ${instRs(_items[i].cashPrice)}',
                          ].where((x) => x.isNotEmpty).join('  •  '),
                          style: TextStyle(color: p.textMuted, fontSize: 12),
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: Loc.t('One more like this', 'ایسا ایک اور'),
                            icon: Icon(Icons.copy_outlined, color: p.teal),
                            onPressed: () => _copy(_items[i]),
                          ),
                          IconButton(
                            tooltip: Loc.t('Remove', 'ہٹائیں'),
                            icon: Icon(Icons.close, color: p.textMuted),
                            onPressed: () => setState(() => _items.removeAt(i)),
                          ),
                        ]),
                      ),
                    ),
                  if (_items.isNotEmpty) ...[
                    // Same model: rate dobara na likhna pare.
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: p.teal, minimumSize: const Size.fromHeight(48)),
                      onPressed: () => _copy(_items.last),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: Text(Loc.t('Same model again (only new IMEI)', 'یہی ماڈل دوبارہ (صرف نیا IMEI)')),
                    ),
                    if (kShowScan && (Platform.isAndroid || Platform.isIOS)) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: p.navyLight, minimumSize: const Size.fromHeight(48)),
                        onPressed: _scanMany,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(Loc.t('Same model: scan many boxes', 'یہی ماڈل: کئی ڈبے اسکین کریں')),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _addPiece(),
                    icon: const Icon(Icons.add),
                    label: Text(_items.isEmpty ? Loc.t('Add piece', 'پیس شامل کریں') : Loc.t('Different model', 'دوسرا ماڈل')),
                  ),
                  instSectionTitle(p, Loc.t('PAYMENT', 'ادائیگی')),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: instCard(p),
                    child: Row(children: [
                      Text(Loc.t('Bill total', 'بل کی رقم'), style: TextStyle(color: p.textMuted)),
                      const Spacer(),
                      Text(instRs(total), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 18)),
                    ]),
                  ),
                  gap(),
                  TextField(
                    controller: _paid,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _money,
                    onChanged: (_) => setState(() {}),
                    decoration: instDeco(p, Loc.t('Paid now (0 = all on credit)', 'ابھی ادا کیے (0 = سب ادھار)')),
                  ),
                  if (paid > 0) ...[
                    gap(),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'cash', label: Text(Loc.t('Cash', 'کیش')), icon: const Icon(Icons.payments_outlined)),
                        ButtonSegment(value: 'bank', label: Text(Loc.t('Bank', 'بینک')), icon: const Icon(Icons.account_balance_outlined)),
                      ],
                      selected: {_method},
                      onSelectionChanged: (s) => setState(() => _method = s.first),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                    child: Text(
                      '${Loc.t('Remaining on credit', 'باقی ادھار')}: ${instRs(total - paid)}',
                      style: TextStyle(color: total - paid > 0.5 ? p.red : p.teal, fontWeight: FontWeight.bold),
                    ),
                  ),
                  gap(),
                  TextField(controller: _note, maxLines: 2, decoration: instDeco(p, Loc.t('Note', 'نوٹ'))),
                  const SizedBox(height: 20),
                  instPrimaryButton(
                      p, _saving ? Loc.t('Saving...', 'محفوظ ہو رہا ہے...') : Loc.t('Save Purchase', 'خریداری محفوظ کریں'), _saving ? null : _save),
                ]),
        ),
      ]),
    );
  }
}

// ===================================================================== bill detail

class InstPurchaseDetailScreen extends StatefulWidget {
  final int purchaseId;
  const InstPurchaseDetailScreen({super.key, required this.purchaseId});

  @override
  State<InstPurchaseDetailScreen> createState() => _InstPurchaseDetailScreenState();
}

class _InstPurchaseDetailScreenState extends State<InstPurchaseDetailScreen> {
  InstPurchase? _bill;
  List<InstItem> _items = const [];
  List<InstSupplierPayment> _pays = const [];
  List<PurchaseReturn> _rets = const [];
  List<InstCategory> _cats = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = InstPurchaseRepository.instance;
    final b = await repo.purchase(widget.purchaseId);
    final items = b == null ? const <InstItem>[] : await repo.purchaseItems(b.id);
    final pays = b == null ? const <InstSupplierPayment>[] : await repo.payments(purchaseId: b.id);
    final rets = b == null ? const <PurchaseReturn>[] : await repo.returns(purchaseId: b.id);
    final cats = await InstRepository.instance.categories();
    if (!mounted) return;
    setState(() {
      _bill = b;
      _items = items;
      _pays = pays;
      _rets = rets;
      _cats = cats;
      _loaded = true;
    });
  }

  Future<void> _pay() async {
    final b = _bill;
    if (b == null) return;
    final ok = await showSupplierPayDialog(context, supplierId: b.supplierId, purchase: b);
    if (ok == true) await _reload();
  }

  Future<void> _edit() async {
    final b = _bill;
    if (b == null) return;
    final bill = TextEditingController(text: b.billNo);
    final note = TextEditingController(text: b.note);
    var date = b.purchaseDate;
    final p = ThemeManager.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(Loc.t('Edit bill', 'بل میں تبدیلی')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: bill, decoration: instDeco(p, Loc.t('Bill no.', 'بل نمبر'))),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.fromMillisecondsSinceEpoch(date > 0 ? date : DateTime.now().millisecondsSinceEpoch),
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now());
                if (d != null) setD(() => date = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch);
              },
              child: InputDecorator(
                decoration: instDeco(p, Loc.t('Date', 'تاریخ'), suffix: const Icon(Icons.event)),
                child: Text(_date(date)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: note, maxLines: 2, decoration: instDeco(p, Loc.t('Note', 'نوٹ'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Save', 'محفوظ'))),
          ],
        ),
      ),
    );
    // Controllers dispose nahi kiye: dialog ki band hone wali animation abhi unhein istemal kar rahi hoti hai.
    if (ok != true) return;
    try {
      await InstPurchaseRepository.instance.updatePurchase(b, billNo: bill.text, purchaseDate: date, note: note.text);
      await _reload();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _delete() async {
    final b = _bill;
    if (b == null) return;
    final ok = await instConfirm(
      context,
      Loc.t('Delete this bill?', 'یہ بل حذف کریں؟'),
      Loc.t('${b.billNo}: its ${_items.length} pieces will be removed from stock and its payments cancelled.',
          '${b.billNo}: اس کے ${_items.length} پیس اسٹاک سے نکل جائیں گے اور ادائیگیاں منسوخ ہوں گی۔'),
    );
    if (!ok) return;
    try {
      await InstPurchaseRepository.instance.deletePurchase(b);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _deletePay(InstSupplierPayment pay) async {
    final ok = await instConfirm(context, Loc.t('Cancel this payment?', 'یہ ادائیگی منسوخ کریں؟'),
        '${instRs(pay.amount)}  •  ${_date(pay.paidAt)}');
    if (!ok) return;
    try {
      await InstPurchaseRepository.instance.deletePayment(pay);
      await _reload();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _addPiece() async {
    final b = _bill;
    if (b == null || _cats.isEmpty) return;
    final it = await Navigator.of(context).push<InstItem>(MaterialPageRoute(
        builder: (_) => InstItemFormScreen(
              categories: _cats,
              draft: true,
              initialCategoryId: _items.isEmpty ? null : _items.last.categoryId,
            )));
    if (it == null || !mounted) return;
    try {
      await InstPurchaseRepository.instance.addItems(b, [it]);
      await _reload();
      if (mounted) instToast(context, Loc.t('Piece added to the bill.', 'پیس بل میں شامل ہو گیا۔'));
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _returnPieces() async {
    final b = _bill;
    if (b == null) return;
    final inStock = _items.where((i) => i.inStock).toList();
    if (inStock.isEmpty) {
      return instToast(context, Loc.t('No piece of this bill is in stock.', 'اس بل کا کوئی پیس اسٹاک میں نہیں۔'));
    }
    final p = ThemeManager.palette;
    final chosen = <int>{};
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final sum = inStock.where((i) => chosen.contains(i.id)).fold<double>(0, (a, i) => a + i.costPrice);
          return AlertDialog(
            title: Text(Loc.t('Return to supplier', 'سپلائر کو واپس')),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final it in inStock)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: chosen.contains(it.id),
                      onChanged: (v) => setD(() => v == true ? chosen.add(it.id!) : chosen.remove(it.id)),
                      title: Text(it.title.isEmpty ? it.model : it.title),
                      subtitle: Text([if (it.primaryId.isNotEmpty) it.primaryId, instRs(it.costPrice)].join('  •  ')),
                    ),
                  const SizedBox(height: 8),
                  TextField(controller: note, decoration: instDeco(p, Loc.t('Reason / note', 'وجہ / نوٹ'))),
                  const SizedBox(height: 8),
                  Text('${Loc.t('Payable goes down by', 'دینا کم ہوگا')}: ${instRs(sum)}',
                      style: TextStyle(color: p.teal, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
              TextButton(
                  onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(Loc.t('Return', 'واپس کریں'))),
            ],
          );
        },
      ),
    );
    // Controller dispose nahi kiya: dialog ki band hone wali animation abhi isay istemal kar rahi hoti hai.
    if (ok != true) return;
    try {
      final n = await InstPurchaseRepository.instance
          .returnPieces(b, inStock.where((i) => chosen.contains(i.id)).toList(), note: note.text);
      await _reload();
      if (mounted) instToast(context, Loc.t('$n pieces returned.', '$n پیس واپس ہو گئے۔'));
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _cancelReturn(PurchaseReturn r) async {
    final ok = await instConfirm(context, Loc.t('Undo this return?', 'یہ واپسی ختم کریں؟'),
        Loc.t('${r.itemTitle} goes back into stock.', '${r.itemTitle} دوبارہ اسٹاک میں آ جائے گا۔'));
    if (!ok) return;
    try {
      await InstPurchaseRepository.instance.cancelReturn(r);
      await _reload();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _openItem(InstItem it) async {
    if (_cats.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstItemFormScreen(categories: _cats, existing: it)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final b = _bill;
    final catName = {for (final c in _cats) c.id: c.name};
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, b == null ? Loc.t('Bill', 'بل') : '${Loc.t('Bill', 'بل')} ${b.billNo}', b?.supplierName ?? '',
            actions: [
              if (b != null) ...[
                IconButton(tooltip: Loc.t('Edit', 'تبدیلی'), icon: const Icon(Icons.edit_outlined, color: Colors.white), onPressed: _edit),
                IconButton(tooltip: Loc.t('Delete', 'حذف'), icon: const Icon(Icons.delete_outline, color: Colors.white), onPressed: _delete),
              ],
            ]),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : b == null
                  ? Center(child: Text(Loc.t('Bill not found.', 'بل نہیں ملا۔'), style: TextStyle(color: p.textMuted)))
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: instCard(p),
                        child: Column(children: [
                          instInfoLine(p, Loc.t('Supplier', 'سپلائر'), b.supplierName),
                          instInfoLine(p, Loc.t('Date', 'تاریخ'), _date(b.purchaseDate)),
                          instInfoLine(p, Loc.t('Bill total', 'بل کی رقم'), instRs(b.total)),
                          instInfoLine(p, Loc.t('Paid', 'ادا'), instRs(b.paid)),
                          if (b.returned > 0.005) instInfoLine(p, Loc.t('Returned', 'واپس'), instRs(b.returned)),
                          instInfoLine(p, Loc.t('Due', 'باقی'), instRs(b.due)),
                          instInfoLine(p, Loc.t('Note', 'نوٹ'), b.note),
                          instInfoLine(p, Loc.t('Entered by', 'اندراج'), b.createdBy),
                        ]),
                      ),
                      if (b.due > 0.5) ...[
                        const SizedBox(height: 12),
                        instPrimaryButton(p, Loc.t('Pay supplier', 'سپلائر کو ادائیگی'), _pay, icon: Icons.payments_outlined),
                      ],
                      instSectionTitle(p, Loc.t('PIECES (${_items.length})', 'پیس (${_items.length})')),
                      for (final it in _items)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: instCard(p),
                          child: ListTile(
                            onTap: () => _openItem(it),
                            title: Text(it.title.isEmpty ? it.model : it.title,
                                style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              [catName[it.categoryId] ?? '', if (it.primaryId.isNotEmpty) it.primaryId, instStatusLabel(it.status)]
                                  .where((x) => x.isNotEmpty)
                                  .join('  •  '),
                              style: TextStyle(color: p.textMuted, fontSize: 12),
                            ),
                            trailing: Text(instRs(it.costPrice), style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                            onPressed: _addPiece,
                            icon: const Icon(Icons.add),
                            label: Text(Loc.t('Add piece', 'پیس شامل کریں')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                            onPressed: _returnPieces,
                            icon: const Icon(Icons.assignment_return_outlined),
                            label: Text(Loc.t('Return', 'واپس کریں')),
                          ),
                        ),
                      ]),
                      if (_rets.isNotEmpty) instSectionTitle(p, Loc.t('RETURNED TO SUPPLIER', 'سپلائر کو واپس')),
                      for (final r in _rets)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: instCard(p),
                          child: ListTile(
                            title: Text(r.itemTitle, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                            subtitle: Text([_date(r.returnedAt), r.itemCode, r.note].where((x) => x.isNotEmpty).join('  •  '),
                                style: TextStyle(color: p.textMuted, fontSize: 12)),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('− ${instRs(r.amount)}', style: TextStyle(color: p.teal, fontWeight: FontWeight.bold)),
                              IconButton(
                                tooltip: Loc.t('Undo return', 'واپسی ختم'),
                                icon: Icon(Icons.undo, color: p.textMuted),
                                onPressed: () => _cancelReturn(r),
                              ),
                            ]),
                          ),
                        ),
                      if (_pays.isNotEmpty) instSectionTitle(p, Loc.t('PAYMENTS', 'ادائیگیاں')),
                      for (final pay in _pays)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: instCard(p),
                          child: ListTile(
                            title: Text(instRs(pay.amount), style: TextStyle(color: p.teal, fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              [_date(pay.paidAt), pay.method == 'bank' ? Loc.t('Bank', 'بینک') : Loc.t('Cash', 'کیش'), pay.note, pay.paidBy]
                                  .where((x) => x.isNotEmpty)
                                  .join('  •  '),
                              style: TextStyle(color: p.textMuted, fontSize: 12),
                            ),
                            trailing: IconButton(
                              tooltip: Loc.t('Cancel payment', 'ادائیگی منسوخ'),
                              icon: Icon(Icons.delete_outline, color: p.textMuted),
                              onPressed: () => _deletePay(pay),
                            ),
                          ),
                        ),
                    ]),
        ),
      ]),
    );
  }
}

// ===================================================================== suppliers

class InstSuppliersScreen extends StatefulWidget {
  const InstSuppliersScreen({super.key});

  @override
  State<InstSuppliersScreen> createState() => _InstSuppliersScreenState();
}

class _InstSuppliersScreenState extends State<InstSuppliersScreen> {
  List<InstSupplierRow> _all = const [];
  bool _loaded = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final s = await InstPurchaseRepository.instance.suppliers();
    if (!mounted) return;
    setState(() {
      _all = s;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? _all : _all.where((r) => '${r.supplier.name} ${r.supplier.phone}'.toLowerCase().contains(q)).toList();
    final payable = _all.fold<double>(0, (a, r) => a + r.balance);
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.teal,
        foregroundColor: Colors.white,
        onPressed: () async {
          final id = await showSupplierDialog(context);
          if (id != null) await _reload();
        },
        icon: const Icon(Icons.person_add_alt),
        label: Text(Loc.t('New Supplier', 'نیا سپلائر')),
      ),
      body: Column(children: [
        instHeader(context, p, Loc.t('Suppliers', 'سپلائرز'),
            '${Loc.t('Total to pay', 'کل دینا')}: ${instRs(payable)}'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: instDeco(p, Loc.t('Search name, phone', 'نام، فون سے تلاش'), suffix: const Icon(Icons.search)),
          ),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? Center(
                      child: Text(
                        _all.isEmpty ? Loc.t('No suppliers yet.', 'ابھی کوئی سپلائر نہیں۔') : Loc.t('Nothing found.', 'کچھ نہیں ملا۔'),
                        style: TextStyle(color: p.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final r = list[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: instCard(p),
                          child: ListTile(
                            onTap: () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => InstSupplierLedgerScreen(supplierId: r.supplier.id!)));
                              await _reload();
                            },
                            title: Text(r.supplier.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              [r.supplier.phone, '${Loc.t('Bought', 'خریدا')} ${instRs(r.purchased)}'].where((x) => x.isNotEmpty).join('  •  '),
                              style: TextStyle(color: p.textMuted, fontSize: 12),
                            ),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(instRs(r.balance),
                                  style: TextStyle(color: r.balance > 0.5 ? p.red : p.teal, fontWeight: FontWeight.bold)),
                              Text(r.balance > 0.5 ? Loc.t('to pay', 'دینا ہے') : Loc.t('clear', 'صاف'),
                                  style: TextStyle(color: p.textMuted, fontSize: 11)),
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

// ===================================================================== supplier ledger

class InstSupplierLedgerScreen extends StatefulWidget {
  final int supplierId;
  const InstSupplierLedgerScreen({super.key, required this.supplierId});

  @override
  State<InstSupplierLedgerScreen> createState() => _InstSupplierLedgerScreenState();
}

class _InstSupplierLedgerScreenState extends State<InstSupplierLedgerScreen> {
  InstSupplierRow? _row;
  List<SupplierLedgerLine> _lines = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = InstPurchaseRepository.instance;
    final r = await repo.supplierRow(widget.supplierId);
    final l = await repo.ledger(widget.supplierId);
    if (!mounted) return;
    setState(() {
      _row = r;
      _lines = l;
      _loaded = true;
    });
  }

  Future<void> _deleteSupplier() async {
    final r = _row;
    if (r == null) return;
    final ok = await instConfirm(context, Loc.t('Delete supplier?', 'سپلائر حذف کریں؟'), r.supplier.name);
    if (!ok) return;
    try {
      await InstPurchaseRepository.instance.deleteSupplier(r.supplier.id!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _deletePay(InstSupplierPayment pay) async {
    final ok = await instConfirm(context, Loc.t('Cancel this payment?', 'یہ ادائیگی منسوخ کریں؟'),
        '${instRs(pay.amount)}  •  ${_date(pay.paidAt)}');
    if (!ok) return;
    try {
      await InstPurchaseRepository.instance.deletePayment(pay);
      await _reload();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _cancelReturn(PurchaseReturn r) async {
    final ok = await instConfirm(context, Loc.t('Undo this return?', 'یہ واپسی ختم کریں؟'),
        Loc.t('${r.itemTitle} goes back into stock.', '${r.itemTitle} دوبارہ اسٹاک میں آ جائے گا۔'));
    if (!ok) return;
    try {
      await InstPurchaseRepository.instance.cancelReturn(r);
      await _reload();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final r = _row;
    final lines = _lines.reversed.toList(); // naye upar
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, r?.supplier.name ?? Loc.t('Supplier', 'سپلائر'), r?.supplier.phone ?? '', actions: [
          if (r != null) ...[
            IconButton(
              tooltip: Loc.t('Edit', 'تبدیلی'),
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              onPressed: () async {
                final id = await showSupplierDialog(context, existing: r.supplier);
                if (id != null) await _reload();
              },
            ),
            IconButton(
              tooltip: 'PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
              onPressed: () => InstPdf.shareTable(
                context,
                base: 'Supplier_${r.supplier.name}',
                title: Loc.t('Supplier Account', 'سپلائر کھاتہ'),
                sub: r.supplier.name,
                summary: [
                  (Loc.t('Total bought', 'کل خریداری'), instRs(r.purchased)),
                  (Loc.t('Total paid', 'کل ادا'), instRs(r.paid)),
                  if (r.returned > 0.005) (Loc.t('Returned goods', 'واپس کیا مال'), instRs(r.returned)),
                  (Loc.t('To pay', 'دینا ہے'), instRs(r.balance)),
                ],
                headers: [Loc.t('Date', 'تاریخ'), Loc.t('Detail', 'تفصیل'), Loc.t('Bill +', 'بل +'), Loc.t('Paid −', 'ادا −'), Loc.t('Balance', 'باقی')],
                flex: const [2, 5, 2, 2, 2],
                right: const {2, 3, 4},
                rows: [
                  for (final l in _lines)
                    [_date(l.date), l.label, l.bill > 0 ? instRs(l.bill) : '', l.paid > 0 ? instRs(l.paid) : '', instRs(l.balance)]
                ],
              ),
            ),
            IconButton(
                tooltip: Loc.t('Delete', 'حذف'), icon: const Icon(Icons.delete_outline, color: Colors.white), onPressed: _deleteSupplier),
          ],
        ]),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : r == null
                  ? Center(child: Text(Loc.t('Supplier not found.', 'سپلائر نہیں ملا۔'), style: TextStyle(color: p.textMuted)))
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: instCard(p),
                        child: Column(children: [
                          Row(children: [
                            Text(Loc.t('To pay', 'دینا ہے'), style: TextStyle(color: p.textMuted)),
                            const Spacer(),
                            Text(instRs(r.balance),
                                style: TextStyle(color: r.balance > 0.5 ? p.red : p.teal, fontWeight: FontWeight.bold, fontSize: 20)),
                          ]),
                          const SizedBox(height: 6),
                          instInfoLine(p, Loc.t('Total bought', 'کل خریداری'), instRs(r.purchased)),
                          instInfoLine(p, Loc.t('Total paid', 'کل ادا'), instRs(r.paid)),
                          if (r.returned > 0.005) instInfoLine(p, Loc.t('Returned goods', 'واپس کیا مال'), instRs(r.returned)),
                          if (r.supplier.openingBalance.abs() >= 0.005)
                            instInfoLine(p, Loc.t('Old balance', 'پرانا باقی'), instRs(r.supplier.openingBalance)),
                          instInfoLine(p, Loc.t('Address', 'پتہ'), r.supplier.address),
                          instInfoLine(p, Loc.t('Note', 'نوٹ'), r.supplier.note),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            onPressed: () async {
                              await Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => InstNewPurchaseScreen(supplierId: r.supplier.id)));
                              await _reload();
                            },
                            icon: const Icon(Icons.add_shopping_cart),
                            label: Text(Loc.t('New bill', 'نیا بل')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: p.teal, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                            onPressed: () async {
                              final ok = await showSupplierPayDialog(context, supplierId: r.supplier.id!, suggested: r.balance);
                              if (ok == true) await _reload();
                            },
                            icon: const Icon(Icons.payments_outlined),
                            label: Text(Loc.t('Pay', 'ادائیگی')),
                          ),
                        ),
                      ]),
                      instSectionTitle(p, Loc.t('ACCOUNT', 'کھاتہ')),
                      if (lines.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(Loc.t('No entries yet.', 'ابھی کوئی اندراج نہیں۔'), style: TextStyle(color: p.textMuted)),
                        ),
                      for (final l in lines)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: instCard(p),
                          child: ListTile(
                            onTap: l.payment == null && l.purchaseId != null
                                ? () async {
                                    await Navigator.of(context)
                                        .push(MaterialPageRoute(builder: (_) => InstPurchaseDetailScreen(purchaseId: l.purchaseId!)));
                                    await _reload();
                                  }
                                : null,
                            onLongPress: l.payment != null
                                ? () => _deletePay(l.payment!)
                                : (l.ret != null ? () => _cancelReturn(l.ret!) : null),
                            title: Text(l.label, style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
                            subtitle: Text('${_date(l.date)}  •  ${Loc.t('Balance', 'باقی')} ${instRs(l.balance)}',
                                style: TextStyle(color: p.textMuted, fontSize: 12)),
                            trailing: Text(
                              l.bill > 0 ? '+ ${instRs(l.bill)}' : '− ${instRs(l.paid)}',
                              style: TextStyle(color: l.bill > 0 ? p.red : p.teal, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      if (lines.any((l) => l.payment != null || l.ret != null))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(Loc.t('Long-press a payment / return to cancel it.', 'ادائیگی / واپسی منسوخ کرنے کے لیے اسے دبا کر رکھیں۔'),
                              style: TextStyle(color: p.textMuted, fontSize: 11.5)),
                        ),
                    ]),
        ),
      ]),
    );
  }
}

// ===================================================================== dialogs

/// Haan / Nahi. Wapas true = haan.
Future<bool> instConfirm(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('No', 'نہیں'))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Yes', 'ہاں'))),
      ],
    ),
  );
  return ok == true;
}

/// Naya / purana supplier. Wapas: supplier id (null = cancel / ghalti, toast dikh chuka).
Future<int?> showSupplierDialog(BuildContext context, {InstSupplier? existing}) async {
  final p = ThemeManager.palette;
  final name = TextEditingController(text: existing?.name ?? '');
  final phone = TextEditingController(text: existing?.phone ?? '');
  final address = TextEditingController(text: existing?.address ?? '');
  final opening = TextEditingController(
      text: existing == null || existing.openingBalance.abs() < 0.005 ? '' : instPlain(existing.openingBalance));
  final note = TextEditingController(text: existing?.note ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? Loc.t('New Supplier', 'نیا سپلائر') : Loc.t('Edit Supplier', 'سپلائر میں تبدیلی')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              autofocus: existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: instDeco(p, Loc.t('Name *', 'نام *'), hint: 'Ali Mobiles, Lahore')),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: instDeco(p, Loc.t('Phone', 'فون'))),
          const SizedBox(height: 12),
          TextField(controller: address, decoration: instDeco(p, Loc.t('Address / market', 'پتہ / مارکیٹ'))),
          const SizedBox(height: 12),
          TextField(
            controller: opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
            decoration: instDeco(p, Loc.t('Old balance you owe', 'پرانا باقی جو دینا ہے')),
          ),
          const SizedBox(height: 12),
          TextField(controller: note, maxLines: 2, decoration: instDeco(p, Loc.t('Note', 'نوٹ'))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Save', 'محفوظ'))),
      ],
    ),
  );
  // Controllers dispose nahi kiye: dialog ki band hone wali animation abhi unhein istemal kar rahi hoti hai.
  if (ok != true) return null;
  try {
    return await InstPurchaseRepository.instance.saveSupplier(InstSupplier(
      id: existing?.id,
      name: name.text,
      phone: phone.text,
      address: address.text,
      note: note.text,
      openingBalance: instParse(opening.text),
      createdAt: existing?.createdAt ?? 0,
    ));
  } catch (e) {
    if (context.mounted) instToast(context, instErr(e));
    return null;
  }
}

/// Supplier ko adaigi. [purchase] di ho to usi bill ki. Wapas true = ho gayi.
Future<bool> showSupplierPayDialog(BuildContext context, {required int supplierId, InstPurchase? purchase, double? suggested}) async {
  final p = ThemeManager.palette;
  final start = purchase?.due ?? suggested ?? 0;
  final amount = TextEditingController(text: start > 0.5 ? instPlain(start) : '');
  final note = TextEditingController();
  var method = 'cash';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(purchase == null ? Loc.t('Pay supplier', 'سپلائر کو ادائیگی') : '${Loc.t('Pay bill', 'بل کی ادائیگی')} ${purchase.billNo}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (start > 0.5)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('${Loc.t('Due', 'باقی')}: ${instRs(start)}', style: TextStyle(color: p.red, fontWeight: FontWeight.bold)),
              ),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _money,
              decoration: instDeco(p, Loc.t('Amount *', 'رقم *')),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'cash', label: Text(Loc.t('Cash', 'کیش'))),
                ButtonSegment(value: 'bank', label: Text(Loc.t('Bank', 'بینک'))),
              ],
              selected: {method},
              onSelectionChanged: (s) => setD(() => method = s.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: instDeco(p, Loc.t('Note', 'نوٹ'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Pay', 'ادا کریں'))),
        ],
      ),
    ),
  );
  // Controllers dispose nahi kiye: dialog ki band hone wali animation abhi unhein istemal kar rahi hoti hai.
  if (ok != true) return false;
  try {
    await InstPurchaseRepository.instance.pay(
      supplierId: supplierId,
      purchaseId: purchase?.id,
      amount: instParse(amount.text),
      method: method,
      note: note.text,
    );
    return true;
  } catch (e) {
    if (context.mounted) instToast(context, instErr(e));
    return false;
  }
}
