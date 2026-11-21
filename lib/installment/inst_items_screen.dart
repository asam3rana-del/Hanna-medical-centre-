import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_cash_sale_repository.dart';
import 'inst_cash_sale_screens.dart';
import 'inst_models.dart';
import 'inst_plan_repository.dart';
import 'inst_plans_screen.dart';
import 'inst_rate_screen.dart';
import 'inst_repository.dart';
import 'inst_scan.dart';
import 'inst_ui.dart';

String instStatusLabel(String s) => switch (s) {
      itemInStock => Loc.t('In stock', 'اسٹاک میں'),
      itemSold => Loc.t('Sold', 'فروخت'),
      itemReturned => Loc.t('Returned', 'واپس'),
      itemRepossessed => Loc.t('Taken back', 'واپس لیا'),
      _ => s,
    };

Color _statusColor(AppPalette p, String s) => switch (s) {
      itemInStock => p.teal,
      itemSold => p.blue,
      itemRepossessed => p.red,
      _ => p.amber,
    };

// ===================================================================== stock list

class InstItemsScreen extends StatefulWidget {
  const InstItemsScreen({super.key});

  @override
  State<InstItemsScreen> createState() => _InstItemsScreenState();
}

class _InstItemsScreenState extends State<InstItemsScreen> {
  List<InstItem> _all = const [];
  List<InstCategory> _cats = const [];
  bool _loaded = false;
  String _q = '';
  int? _catId;
  String? _status = itemInStock;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = InstRepository.instance;
    final cats = await repo.categories();
    final items = await repo.items();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _all = items;
      _loaded = true;
      if (_catId != null && !cats.any((c) => c.id == _catId)) _catId = null;
    });
  }

  Future<void> _edit([InstItem? item]) async {
    if (_cats.isEmpty) {
      instToast(context, Loc.t('Add a category first.', 'پہلے کیٹیگری بنائیں۔'));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InstItemFormScreen(categories: _cats, existing: item, initialCategoryId: _catId)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final catName = {for (final c in _cats) c.id: c.name};
    final list = _all
        .where((i) => (_catId == null || i.categoryId == _catId) && (_status == null || i.status == _status) && i.matches(_q))
        .toList();
    final showCost = Session.isAdminOrManager;
    final totalCost = list.fold<double>(0, (a, i) => a + i.costPrice);
    final totalCash = list.fold<double>(0, (a, i) => a + i.cashPrice);
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.teal,
        foregroundColor: Colors.white,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(Loc.t('Add Item', 'سامان شامل کریں')),
      ),
      body: Column(children: [
        instHeader(context, p, Loc.t('Stock', 'اسٹاک'), Loc.t('Every piece with its IMEI / serial', 'ہر پیس اپنے IMEI / سیریل کے ساتھ'),
            actions: [
              if (Session.isAdminOrManager)
                IconButton(
                  tooltip: Loc.t('Change rates', 'ریٹ بدلیں'),
                  icon: const Icon(Icons.price_change_outlined, color: Colors.white),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InstRateChangeScreen()));
                    await _reload();
                  },
                ),
              IconButton(
                tooltip: Loc.t('Categories', 'کیٹیگریز'),
                icon: const Icon(Icons.category_outlined, color: Colors.white),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InstCategoriesScreen()));
                  await _reload();
                },
              ),
            ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: instDeco(p, Loc.t('Search model, IMEI, serial, engine no.', 'ماڈل، IMEI، سیریل، انجن نمبر سے تلاش'),
                suffix: const Icon(Icons.search)),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            _chip(Loc.t('All', 'سب'), _catId == null, () => setState(() => _catId = null)),
            for (final c in _cats) _chip(c.name, _catId == c.id, () => setState(() => _catId = c.id)),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final s in itemStatuses) _chip(instStatusLabel(s), _status == s, () => setState(() => _status = s)),
            _chip(Loc.t('Any status', 'ہر حالت'), _status == null, () => setState(() => _status = null)),
          ]),
        ),
        if (_loaded && list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(children: [
              Text(Loc.t('${list.length} pieces', '${list.length} پیس'), style: TextStyle(color: p.textMuted, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                showCost
                    ? '${Loc.t('Cost', 'لاگت')} ${instRs(totalCost)}  •  ${Loc.t('Cash', 'نقد')} ${instRs(totalCash)}'
                    : '${Loc.t('Cash', 'نقد')} ${instRs(totalCash)}',
                style: TextStyle(color: p.textMuted, fontSize: 12),
              ),
            ]),
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
                                ? Loc.t('No items yet. Tap "Add Item".', 'ابھی کوئی سامان نہیں۔ "سامان شامل کریں" دبائیں۔')
                                : Loc.t('Nothing found.', 'کچھ نہیں ملا۔'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.textMuted)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _tile(p, list[i], catName[list[i].categoryId] ?? '', showCost),
                    ),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  Widget _tile(AppPalette p, InstItem i, String cat, bool showCost) {
    final c = _statusColor(p, i.status);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _edit(i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: instCard(p),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title.isEmpty ? i.model : i.title,
                  style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15.5)),
              Text([cat, if (i.color.isNotEmpty) i.color].join('  •  '), style: TextStyle(color: p.textMuted, fontSize: 12)),
              if (i.primaryId.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(i.primaryId, style: TextStyle(color: p.textDark, fontSize: 12.5, letterSpacing: 0.3)),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(instRs(i.cashPrice), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
            if (showCost && i.costPrice > 0)
              Text('${Loc.t('Cost', 'لاگت')} ${instRs(i.costPrice)}', style: TextStyle(color: p.textMuted, fontSize: 11)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(instStatusLabel(i.status), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ===================================================================== item form

class InstItemFormScreen extends StatefulWidget {
  final List<InstCategory> categories;
  final InstItem? existing;
  final int? initialCategoryId;

  /// Khareed ke bill ka piece: save nahi hota, bana hua [InstItem] `Navigator.pop` se wapas (bill saath save karta hai).
  final bool draft;

  /// Draft mein pichle piece ki copy (model / qeemat wahi, pehchan number khali).
  final InstItem? template;
  const InstItemFormScreen(
      {super.key, required this.categories, this.existing, this.initialCategoryId, this.draft = false, this.template});

  @override
  State<InstItemFormScreen> createState() => _InstItemFormScreenState();
}

class _InstItemFormScreenState extends State<InstItemFormScreen> {
  late final InstItem? _init = widget.existing ?? widget.template;
  late int _catId = _init?.categoryId ?? widget.initialCategoryId ?? widget.categories.first.id!;
  late final _brand = TextEditingController(text: _init?.brand ?? '');
  late final _model = TextEditingController(text: _init?.model ?? '');
  late final _color = TextEditingController(text: _init?.color ?? '');
  late final _cost = TextEditingController(text: _num(_init?.costPrice));
  late final _cash = TextEditingController(text: _num(_init?.cashPrice));
  late final _warranty = TextEditingController(text: (_init?.warrantyMonths ?? 0) > 0 ? '${_init!.warrantyMonths}' : '');
  late final _supplier = TextEditingController(text: widget.existing?.supplier ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late int _purchaseDate = widget.existing?.purchaseDate ?? 0;
  late String _status = widget.existing?.status ?? itemInStock;

  /// Field ka naam -> controller. Category badalne par naye fields; purani bhari value na mitti (wapas aane par mile).
  final Map<String, TextEditingController> _ids = {};
  List<PriceChange> _history = const [];
  bool _saving = false;

  static String _num(double? v) => v == null || v == 0 ? '' : instPlain(v);

  bool get _editable => widget.existing == null || widget.existing!.inStock;

  Future<void> _openPlan() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final planId = await InstPlanRepository.instance.planIdForItem(id);
    if (!mounted) return;
    if (planId == null) {
      final saleId = await InstCashSaleRepository.instance.saleIdForItem(id);
      if (!mounted) return;
      if (saleId != null) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstCashSaleDetailScreen(saleId: saleId)));
        return;
      }
      return instToast(context, Loc.t('No plan or sale found for this piece.', 'اس پیس کا کوئی پلان یا سیل نہیں ملی۔'));
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstPlanDetailScreen(planId: planId)));
  }

  @override
  void initState() {
    super.initState();
    if (!widget.categories.any((c) => c.id == _catId)) _catId = widget.categories.first.id!;
    for (final e in (_init?.idValues ?? const <String, String>{}).entries) {
      _ids[e.key] = TextEditingController(text: e.value);
    }
    final id = widget.existing?.id;
    if (id != null) {
      InstRepository.instance.priceHistory(id).then((h) {
        if (mounted) setState(() => _history = h);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    for (final c in [_brand, _model, _color, _cost, _cash, _warranty, _supplier, _note, ..._ids.values]) {
      c.dispose();
    }
    super.dispose();
  }

  InstCategory get _cat => widget.categories.firstWhere((c) => c.id == _catId);

  /// Is category ke fields + purane record ke woh fields jo category mein ab nahi (data gum na ho).
  List<String> get _fieldNames {
    final names = [..._cat.idFields];
    for (final k in (widget.existing?.idValues.keys ?? const <String>[])) {
      if (!names.contains(k)) names.add(k);
    }
    return names;
  }

  /// Dabbe ka barcode scan kar ke pehchan number bharo (Step 27). IMEI field: sirf 15 hindse wala barcode lete hain
  /// (dabbe ke EAN / model barcode chhor kar scan chalta rehta hai); doosre fields: jo bhi barcode aaye.
  Future<void> _scanInto(String field) async {
    final imei = field.toLowerCase().contains('imei');
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => InstBarcodeScanPage(accept: (v) => imei ? RegExp(r'^\d{15}$').hasMatch(v.trim()) : v.trim().length >= 4)));
    if (code == null || !mounted) return;
    setState(() => _idCtrl(field).text = code.trim());
  }

  TextEditingController _idCtrl(String name) => _ids.putIfAbsent(name, () => TextEditingController());

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final names = _fieldNames;
    final ex = widget.existing;
    final item = InstItem(
      id: ex?.id,
      categoryId: _catId,
      brand: _brand.text,
      model: _model.text,
      color: _color.text,
      idValues: {for (final n in names) n: _idCtrl(n).text},
      costPrice: Session.isAdminOrManager || widget.draft ? instParse(_cost.text) : (ex?.costPrice ?? 0),
      cashPrice: instParse(_cash.text),
      warrantyMonths: int.tryParse(_warranty.text.trim()) ?? 0,
      supplier: _supplier.text,
      note: _note.text,
      status: _status,
      purchaseDate: _purchaseDate,
      createdAt: ex?.createdAt ?? 0,
    );
    if (widget.draft) {
      setState(() => _saving = false);
      if (item.model.trim().isEmpty) return instToast(context, Loc.t('Enter the model / name.', 'ماڈل / نام لکھیں۔'));
      if (instParse(_cost.text) <= 0) {
        return instToast(context, Loc.t('Enter the purchase cost.', 'خرید قیمت لکھیں۔'));
      }
      Navigator.of(context).pop(item);
      return;
    }
    try {
      await InstRepository.instance.saveItem(item);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        instToast(context, instErr(e));
      }
    }
  }

  Future<void> _delete() async {
    final ex = widget.existing;
    if (ex == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('Delete this item?', 'یہ سامان حذف کریں؟')),
        content: Text('${ex.title}\n${ex.primaryId}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Delete', 'حذف'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await InstRepository.instance.deleteItem(ex);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final init = _purchaseDate > 0 ? DateTime.fromMillisecondsSinceEpoch(_purchaseDate) : now;
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2015), lastDate: now);
    if (d != null) setState(() => _purchaseDate = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    Widget gap() => const SizedBox(height: 12);
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final ex = widget.existing;
    final cost = instParse(_cost.text);
    final cash = instParse(_cash.text);
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(
          context,
          p,
          widget.draft
              ? Loc.t('Piece in bill', 'بل میں پیس')
              : ex == null
                  ? Loc.t('Add Item', 'سامان شامل کریں')
                  : (ex.title.isEmpty ? ex.model : ex.title),
          widget.draft
              ? Loc.t('Supplier and date come from the bill', 'سپلائر اور تاریخ بل سے')
              : ex == null
                  ? Loc.t('One entry = one piece', 'ایک اندراج = ایک پیس')
                  : instStatusLabel(ex.status),
          actions: [
            if (ex != null && ex.inStock && !widget.draft)
              IconButton(tooltip: Loc.t('Delete', 'حذف'), icon: const Icon(Icons.delete_outline, color: Colors.white), onPressed: _delete),
          ],
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            if (!_editable)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      Loc.t('This piece is not in stock. You can fix details, but it cannot be deleted.',
                          'یہ پیس اسٹاک میں نہیں۔ معلومات درست کر سکتے ہیں، حذف نہیں ہو سکتا۔'),
                      style: TextStyle(color: p.textDark)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    if (widget.existing!.status != itemInStock)
                      OutlinedButton.icon(
                          onPressed: _openPlan,
                          icon: const Icon(Icons.request_quote_outlined),
                          label: Text(Loc.t('View plan / sale', 'پلان / سیل دیکھیں'))),
                    if ((widget.existing!.status == itemRepossessed || widget.existing!.status == itemReturned) && Session.isAdminOrManager)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _status = _status == itemInStock ? widget.existing!.status : itemInStock),
                        icon: Icon(_status == itemInStock ? Icons.check_box : Icons.check_box_outline_blank),
                        label: Text(Loc.t('Put back in stock (on save)', 'دوبارہ اسٹاک میں (محفوظ پر)')),
                      ),
                  ]),
                ]),
              ),
            if (ex != null && ex.inStock && !widget.draft && ex.id != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstNewCashSaleScreen(itemId: ex.id)));
                    if (mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.point_of_sale),
                  label: Text(Loc.t('Sell for cash', 'نقد بیچیں')),
                ),
              ),
            instSectionTitle(p, Loc.t('ITEM', 'سامان')),
            DropdownButtonFormField<int>(
              value: _catId,
              decoration: instDeco(p, Loc.t('Category', 'کیٹیگری')),
              items: [for (final c in widget.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) {
                if (v != null) setState(() => _catId = v);
              },
            ),
            gap(),
            TextField(controller: _brand, textCapitalization: TextCapitalization.words, decoration: instDeco(p, Loc.t('Company', 'کمپنی'), hint: 'Samsung, Honda, Haier')),
            gap(),
            TextField(controller: _model, textCapitalization: TextCapitalization.words, decoration: instDeco(p, Loc.t('Model *', 'ماڈل *'), hint: 'A15 128GB / CD-70 / 43" LED')),
            gap(),
            TextField(controller: _color, textCapitalization: TextCapitalization.words, decoration: instDeco(p, Loc.t('Color', 'رنگ'))),
            if (_fieldNames.isNotEmpty) instSectionTitle(p, Loc.t('IDENTIFICATION', 'پہچان نمبر')),
            for (final n in _fieldNames) ...[
              TextField(
                controller: _idCtrl(n),
                textCapitalization: TextCapitalization.characters,
                keyboardType: n.toLowerCase().contains('imei') ? TextInputType.number : TextInputType.text,
                decoration: instDeco(p, n,
                    suffix: kShowScan && (Platform.isAndroid || Platform.isIOS)
                        ? IconButton(
                            tooltip: Loc.t('Scan barcode', 'بارکوڈ اسکین'),
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: () => _scanInto(n),
                          )
                        : null),
              ),
              gap(),
            ],
            instSectionTitle(p, Loc.t('PRICE', 'قیمت')),
            if (Session.isAdminOrManager || widget.draft) ...[
              TextField(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: money,
                onChanged: (_) => setState(() {}),
                decoration: instDeco(p, Loc.t('Purchase cost', 'خرید قیمت')),
              ),
              gap(),
            ],
            TextField(
              controller: _cash,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: money,
              onChanged: (_) => setState(() {}),
              decoration: instDeco(p, Loc.t('Cash sale price', 'نقد قیمت فروخت')),
            ),
            if (kShowProfitOutsideReports && Session.isAdminOrManager && cost > 0 && cash > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Text(
                  '${Loc.t('Cash profit', 'نقد منافع')}: ${instRs(cash - cost)}  (${(((cash - cost) / cost) * 100).toStringAsFixed(1)}%)',
                  style: TextStyle(color: cash >= cost ? p.teal : p.red, fontWeight: FontWeight.bold),
                ),
              ),
            instSectionTitle(p, Loc.t('OTHER', 'دیگر')),
            TextField(
              controller: _warranty,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: instDeco(p, Loc.t('Warranty (months)', 'وارنٹی (مہینے)')),
            ),
            if (!widget.draft) ...[
            gap(),
            TextField(controller: _supplier, decoration: instDeco(p, Loc.t('Bought from (supplier)', 'کہاں سے خریدا (سپلائر)'))),
            gap(),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: instDeco(p, Loc.t('Purchase date', 'خرید کی تاریخ'), suffix: const Icon(Icons.event)),
                child: Text(
                  _purchaseDate > 0 ? DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(_purchaseDate)) : '—',
                  style: TextStyle(color: p.textDark, fontSize: 15),
                ),
              ),
            ),
            ],
            gap(),
            TextField(controller: _note, maxLines: 2, decoration: instDeco(p, Loc.t('Note', 'نوٹ'))),
            if (_history.isNotEmpty) ...[
              instSectionTitle(p, Loc.t('RATE HISTORY', 'ریٹ کی تاریخ')),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: instCard(p),
                child: Column(children: [
                  for (final h in _history)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 92,
                          child: Text(DateFormat('dd MMM yy').format(DateTime.fromMillisecondsSinceEpoch(h.changedAt)),
                              style: TextStyle(color: p.textMuted, fontSize: 12)),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${instRs(h.oldCash)} → ${instRs(h.newCash)}',
                                style: TextStyle(color: h.newCash >= h.oldCash ? p.teal : p.red, fontWeight: FontWeight.w600)),
                            if (h.costChanged && Session.isAdminOrManager)
                              Text('${Loc.t('Cost', 'لاگت')} ${instRs(h.oldCost)} → ${instRs(h.newCost)}',
                                  style: TextStyle(color: p.textMuted, fontSize: 12)),
                            if (h.note.isNotEmpty || h.changedBy.isNotEmpty)
                              Text([h.note, h.changedBy].where((x) => x.isNotEmpty).join(' • '), style: TextStyle(color: p.textMuted, fontSize: 11.5)),
                          ]),
                        ),
                      ]),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            instPrimaryButton(
                p,
                widget.draft
                    ? Loc.t('Add to bill', 'بل میں شامل کریں')
                    : (_saving ? Loc.t('Saving...', 'محفوظ ہو رہا ہے...') : Loc.t('Save', 'محفوظ کریں')),
                _saving ? null : _save),
          ]),
        ),
      ]),
    );
  }
}

// ===================================================================== categories

class InstCategoriesScreen extends StatefulWidget {
  const InstCategoriesScreen({super.key});

  @override
  State<InstCategoriesScreen> createState() => _InstCategoriesScreenState();
}

class _InstCategoriesScreenState extends State<InstCategoriesScreen> {
  List<InstCategory> _cats = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final c = await InstRepository.instance.categories();
    if (!mounted) return;
    setState(() {
      _cats = c;
      _loaded = true;
    });
  }

  Future<void> _edit([InstCategory? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final fields = TextEditingController(text: (c?.idFields ?? const <String>[]).join(', '));
    final p = ThemeManager.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c == null ? Loc.t('New Category', 'نئی کیٹیگری') : Loc.t('Edit Category', 'کیٹیگری میں تبدیلی')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: c == null, textCapitalization: TextCapitalization.words, decoration: instDeco(p, Loc.t('Name', 'نام'), hint: 'Mobile, Motorcycle')),
          const SizedBox(height: 12),
          TextField(
            controller: fields,
            decoration: instDeco(p, Loc.t('ID fields (comma separated)', 'پہچان فیلڈز (کاما سے الگ)'), hint: 'IMEI 1, IMEI 2'),
          ),
          const SizedBox(height: 6),
          Text(
            Loc.t('Example: Engine No., Chassis No.  —  leave empty if none.', 'مثال: Engine No., Chassis No. — نہ ہو تو خالی چھوڑیں۔'),
            style: TextStyle(color: p.textMuted, fontSize: 11.5),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Save', 'محفوظ'))),
        ],
      ),
    );
    // Controllers dispose nahi kiye: dialog ki band hone wali animation abhi unhein istemal kar rahi hoti hai.
    final n = name.text;
    final f = parseIdFields(fields.text);
    if (ok != true) return;
    try {
      await InstRepository.instance.saveCategory(
          c == null ? InstCategory(name: n, idFields: f) : c.copyWith(name: n, idFields: f));
      await _reload();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  Future<void> _delete(InstCategory c) async {
    try {
      await InstRepository.instance.deleteCategory(c.id!);
      await _reload();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.teal,
        foregroundColor: Colors.white,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(Loc.t('New Category', 'نئی کیٹیگری')),
      ),
      body: Column(children: [
        instHeader(context, p, Loc.t('Categories', 'کیٹیگریز'), Loc.t('What you sell on installments', 'جو چیزیں قسط پر بیچتے ہیں')),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                  for (final c in _cats)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: instCard(p),
                      child: ListTile(
                        onTap: () => _edit(c),
                        title: Text(c.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          c.idFields.isEmpty ? Loc.t('No ID fields', 'کوئی پہچان فیلڈ نہیں') : c.idFields.join('  •  '),
                          style: TextStyle(color: p.textMuted, fontSize: 12),
                        ),
                        trailing: IconButton(icon: Icon(Icons.delete_outline, color: p.textMuted), onPressed: () => _delete(c)),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}
