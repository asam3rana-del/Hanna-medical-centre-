import 'package:flutter/material.dart';

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import '../services/session.dart';
import 'inst_customers_screen.dart';
import 'inst_items_screen.dart';
import 'inst_models.dart';
import 'inst_repository.dart';
import 'inst_ui.dart';

/// Dashboard ka search (Step 30): customer ka naam / CNIC / phone / khata no. likhte hi neeche nateeje; tap = customer
/// (sab plans, history). Customers ki list ek dafa parhte hain, data badle to dobara.
class InstHomeSearch extends StatefulWidget {
  const InstHomeSearch({super.key});

  @override
  State<InstHomeSearch> createState() => _InstHomeSearchState();
}

class _InstHomeSearchState extends State<InstHomeSearch> {
  final _q = TextEditingController();
  List<InstCustomerRow>? _all;
  List<InstItem> _items = const [];
  List<InstCategory> _cats = const [];

  @override
  void initState() {
    super.initState();
    InstRepository.instance.changes.addListener(_invalidate);
  }

  @override
  void dispose() {
    InstRepository.instance.changes.removeListener(_invalidate);
    _q.dispose();
    super.dispose();
  }

  void _invalidate() => _all = null;

  Future<void> _ensure() async {
    if (_all != null) return;
    final rows = await InstRepository.instance.listCustomers();
    // Step 31: saman bhi — rate / stock dekhne ke liye.
    final items = await InstRepository.instance.items();
    final cats = await InstRepository.instance.categories();
    if (mounted) {
      setState(() {
        _all = rows;
        _items = items;
        _cats = cats;
      });
    }
  }

  Future<void> _openItem(InstItem it) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstItemFormScreen(categories: _cats, existing: it)));
  }

  Future<void> _open(InstCustomerRow c) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstCustomerDetailScreen(customerId: c.id)));
    if (mounted) setState(() => _q.clear());
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final q = _q.text.trim();
    final all = _all;
    final hits = q.length < 2 || all == null ? const <InstCustomerRow>[] : all.where((c) => c.matches(q)).take(8).toList();
    // Saman: stock wale pehle; kitne pieces stock mein (rate check).
    final itemHits = q.length < 2 || all == null
        ? const <InstItem>[]
        : (_items.where((i) => i.matches(q)).toList()..sort((a, b) => (a.inStock ? 0 : 1) - (b.inStock ? 0 : 1)));
    final inStock = itemHits.where((i) => i.inStock).length;
    final mgr = Session.isAdminOrManager;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _q,
        textInputAction: TextInputAction.search,
        decoration: instDeco(p, Loc.t('Search customer or item: name, CNIC, phone, model, IMEI', 'تلاش: کسٹمر یا سامان — نام، شناختی کارڈ، فون، ماڈل، IMEI'),
            suffix: q.isEmpty
                ? const Icon(Icons.search)
                : IconButton(
                    tooltip: Loc.t('Clear', 'صاف'),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _q.clear()),
                  )),
        onTap: _ensure,
        onChanged: (_) async {
          await _ensure();
          if (mounted) setState(() {});
        },
      ),
      if (q.length >= 2)
        Container(
          margin: const EdgeInsets.only(top: 6),
          decoration: instCard(p),
          child: all == null
              ? const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator()))
              : hits.isEmpty && itemHits.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(Loc.t('Nothing found.', 'کچھ نہیں ملا۔'), style: TextStyle(color: p.textMuted)),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (itemHits.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                          child: Text(Loc.t('STOCK — $inStock in stock', 'اسٹاک — $inStock موجود'),
                              style: TextStyle(color: inStock > 0 ? p.teal : p.red, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        for (final it in itemHits.take(6))
                          ListTile(
                            dense: true,
                            onTap: () => _openItem(it),
                            leading: Icon(Icons.inventory_2_outlined, color: it.inStock ? p.teal : p.textMuted),
                            title: Text(it.title.isEmpty ? it.model : it.title,
                                style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              [
                                instStatusLabel(it.status),
                                if (it.primaryId.isNotEmpty) it.primaryId,
                                if (mgr && it.costPrice > 0) '${Loc.t('Purchase', 'خرید')} ${instRs(it.costPrice)}',
                              ].join('  •  '),
                              style: TextStyle(color: it.inStock ? p.textMuted : p.red, fontSize: 12),
                            ),
                            trailing: it.cashPrice > 0
                                ? Text(instRs(it.cashPrice), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold))
                                : null,
                          ),
                        if (hits.isNotEmpty) const Divider(height: 1),
                      ],
                      if (hits.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                          child: Text(Loc.t('CUSTOMERS', 'کسٹمرز'), style: TextStyle(color: p.navy, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      for (final c in hits)
                        ListTile(
                          dense: true,
                          onTap: () => _open(c),
                          leading: Icon(
                            (c.profile?.isBlocked ?? false) ? Icons.block : Icons.person_outline,
                            color: (c.profile?.isBlocked ?? false) ? p.red : p.navy,
                          ),
                          title: Text(c.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            [
                              if (c.phone.isNotEmpty) c.phone,
                              if ((c.profile?.cnic ?? '').isNotEmpty) c.profile!.cnic,
                              if ((c.profile?.khataNo ?? '').isNotEmpty) '${Loc.t('Khata', 'کھاتہ')} ${c.profile!.khataNo}',
                            ].join('  •  '),
                            style: TextStyle(color: p.textMuted, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                    ]),
        ),
      const SizedBox(height: 14),
    ]);
  }
}
