import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/product_repository.dart';
import '../models/product.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/medical_expiry.dart';

/// Hanna Pharmacy POS: do tabs —
///  1) Expiry: shelf par har batch, filter Expired / 30 din / 90 din / Sab (FIFO andaza, MedicalBatches).
///  2) Dawai / Formula: naam, formula (generic) ya company se search; dawai par tap = batches + substitute.
class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key, this.openSearch = false});

  /// true = seedha "Dawai / Formula" tab.
  final bool openSearch;

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen> {
  static const _all = 1 << 30;
  late bool _search = widget.openSearch;
  int _filterDays = MedicalExpiry.nearDays; // -1 = sirf expired, _all = sab
  final _queryCtrl = TextEditingController();

  List<ActiveBatch>? _batches;
  List<Product> _products = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final products = await ProductRepository.instance.listAll();
      final batches = await MedicalBatches.activeBatches();
      if (mounted) {
        setState(() {
          _products = products;
          _batches = batches;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Color _colorFor(int? d) {
    final p = ThemeManager.palette;
    if (d == null) return p.textMuted;
    if (d <= 30) return p.red;
    if (d <= MedicalExpiry.nearDays) return p.amber;
    return p.teal;
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.navy,
        foregroundColor: Colors.white,
        title: const Text('Medicine & Expiry'),
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : _batches == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(children: [
                        Expanded(child: _tab('Expiry Report', !_search, () => setState(() => _search = false))),
                        const SizedBox(width: 10),
                        Expanded(child: _tab('Dawai / Formula', _search, () => setState(() => _search = true))),
                      ]),
                      const SizedBox(height: 12),
                      if (_search) ..._searchTab() else ..._expiryTab(),
                    ],
                  ),
                ),
    );
  }

  Widget _tab(String label, bool on, VoidCallback onTap) {
    final p = ThemeManager.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? p.navy : p.cardWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: on ? Colors.white : p.textMuted)),
      ),
    );
  }

  // ---------------------------------------------------------------- Expiry tab

  List<Widget> _expiryTab() {
    final p = ThemeManager.palette;
    final batches = _batches!;
    final dated = batches.where((b) => b.daysLeft != null).toList();
    final expired = dated.where((b) => b.daysLeft! < 0).toList();
    final near = dated.where((b) => b.daysLeft! >= 0 && b.daysLeft! <= MedicalExpiry.nearDays).toList();
    final noExpiry = batches.length - dated.length;
    final showCost = Session.isAdminOrManager;
    double value(List<ActiveBatch> l) => l.fold(0.0, (s, b) => s + b.costValue);

    final shown = (_filterDays == -1
        ? expired
        : _filterDays == _all
            ? dated
            : dated.where((b) => b.daysLeft! <= _filterDays).toList())
      ..sort((a, b) => a.daysLeft!.compareTo(b.daysLeft!));

    return [
      Row(children: [
        Expanded(child: _stat('Expired', expired.length, showCost ? 'Rs ${value(expired).round()}' : null, p.red)),
        const SizedBox(width: 10),
        Expanded(child: _stat('${MedicalExpiry.nearDays} din mein', near.length, showCost ? 'Rs ${value(near).round()}' : null, p.amber)),
      ]),
      if (noExpiry > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('$noExpiry stock wale batch ki expiry darj nahi — Purchase mein Expiry likhen ya Product mein.',
              style: TextStyle(fontSize: 12, color: p.textMuted)),
        ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in const [(-1, 'Expired'), (30, '30 din'), (90, '90 din'), (_all, 'Sab')])
          ChoiceChip(
            label: Text(f.$2),
            selected: _filterDays == f.$1,
            onSelected: (_) => setState(() => _filterDays = f.$1),
          ),
      ]),
      const SizedBox(height: 12),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text('Is filter mein koi dawai nahi 👍', style: TextStyle(color: p.textMuted))),
        )
      else
        for (final b in shown) _batchCard(b, showName: true),
    ];
  }

  Widget _stat(String title, int count, String? value, Color color) {
    final p = ThemeManager.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.cardWhite, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 12, color: p.textMuted)),
        Text('$count', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        if (value != null) Text('$value (cost)', style: TextStyle(fontSize: 11.5, color: p.textMuted)),
      ]),
    );
  }

  Widget _batchCard(ActiveBatch b, {required bool showName}) {
    final p = ThemeManager.palette;
    final d = b.daysLeft;
    final color = _colorFor(d);
    final parts = <String>[
      if (showName && b.batchNo.isNotEmpty) 'Batch ${b.batchNo}',
      if (b.expiry.isNotEmpty) 'Exp ${MedicalExpiry.display(b.expiry)}',
      'Stock ~${b.stockText}',
      if (b.product.rackLocation.trim().isNotEmpty) 'Rack ${b.product.rackLocation.trim()}',
    ];
    final src = b.billNo.isEmpty
        ? 'Opening stock / product expiry'
        : [
            'Bill ${b.billNo}',
            if (b.supplierName.isNotEmpty) b.supplierName,
            if (b.purchasedAt > 0) DateFormat('dd MMM yy').format(DateTime.fromMillisecondsSinceEpoch(b.purchasedAt)),
          ].join(' • ');
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: showName ? () => _showDetail(b.product) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.cardWhite, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                showName ? b.product.name : (b.batchNo.isNotEmpty ? 'Batch ${b.batchNo}' : 'Batch —'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.textDark),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Text(d == null ? 'No expiry' : MedicalExpiry.statusLabel(d),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(parts.join('  •  '), style: TextStyle(fontSize: 12.5, color: p.textMuted)),
          const SizedBox(height: 2),
          Text(src, style: TextStyle(fontSize: 11.5, color: p.textMuted)),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- Search tab

  List<Widget> _searchTab() {
    final p = ThemeManager.palette;
    final q = _queryCtrl.text;
    final list = _products.where((x) => x.matchesQuery(q)).take(150).toList();
    return [
      TextField(
        controller: _queryCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Naam, formula ya company likhen…',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: p.fieldFill,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(q.trim().isEmpty ? '${_products.length} dawaiyan • formula se bhi search karen' : '${list.length} mili',
            style: TextStyle(fontSize: 12, color: p.textMuted)),
      ),
      if (list.isEmpty)
        Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Koi dawai nahi mili', style: TextStyle(color: p.textMuted))))
      else
        for (final x in list)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showDetail(x),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.cardWhite, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(x.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.textDark))),
                  Text('Rs ${x.salePrice.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: p.navy)),
                ]),
                if (x.medicalInfoLine.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(x.medicalInfoLine, style: TextStyle(fontSize: 12.5, color: p.teal))),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Stock: ${x.formatStockBreakdown()}', style: TextStyle(fontSize: 12, color: x.stock > 0 ? p.textMuted : p.red)),
                ),
              ]),
            ),
          ),
    ];
  }

  Future<void> _showDetail(Product x) async {
    List<ActiveBatch> own;
    try {
      own = await MedicalBatches.batchesFor(x);
    } catch (_) {
      own = const [];
    }
    own.sort((a, b) => (a.daysLeft ?? _all).compareTo(b.daysLeft ?? _all));
    final subs = MedicalBatches.substitutes(_products, x);
    if (!mounted) return;
    final p = ThemeManager.palette;
    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: p.navy)),
        );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(x.name),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (x.medicalInfoLine.isNotEmpty) Text(x.medicalInfoLine, style: TextStyle(color: p.teal)),
              const SizedBox(height: 6),
              Text('Stock: ${x.formatStockBreakdown()}   •   Rs ${x.salePrice.toStringAsFixed(2)}'),
              title('Batches (shelf par)'),
              if (own.isEmpty) Text('Stock nahi hai', style: TextStyle(color: p.textMuted)),
              for (final b in own) _batchCard(b, showName: false),
              title('Substitute (same formula)'),
              if (x.genericName.trim().isEmpty)
                Text('Is dawai ka formula darj nahi — Product mein Formula likhen', style: TextStyle(color: p.textMuted))
              else if (subs.isEmpty)
                Text('Is formula ki koi aur dawai nahi', style: TextStyle(color: p.textMuted))
              else
                for (final s in subs)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: p.fieldFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s.name}  —  Rs ${s.salePrice.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: s.stock > 0 ? p.textDark : p.textMuted)),
                      Text(
                        [
                          if (s.company.trim().isNotEmpty) s.company.trim(),
                          if (s.rackLocation.trim().isNotEmpty) 'Rack ${s.rackLocation.trim()}',
                          'Stock: ${s.formatStockBreakdown()}',
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: p.textMuted),
                      ),
                    ]),
                  ),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }
}
