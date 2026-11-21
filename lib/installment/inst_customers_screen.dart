import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/party.dart';
import '../services/party_photo_store.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import '../widgets/party_avatar.dart';
import 'inst_cash_sale_repository.dart';
import 'inst_cash_sale_screens.dart';
import 'inst_models.dart';
import 'inst_photo_widgets.dart';
import 'inst_plans_screen.dart';
import 'inst_plan_math.dart' show planActive, planCompleted, planRepossessed;
import 'inst_plan_repository.dart';
import 'inst_repository.dart';
import 'inst_ui.dart';
import 'kyc_photo_store.dart';

// ===================================================================== list

class InstCustomersScreen extends StatefulWidget {
  /// Home ki "ضامن نہیں" warning se: sirf woh customers jin ki profile hai magar guarantor nahi.
  final bool onlyWithoutGuarantor;
  const InstCustomersScreen({super.key, this.onlyWithoutGuarantor = false});

  @override
  State<InstCustomersScreen> createState() => _InstCustomersScreenState();
}

class _InstCustomersScreenState extends State<InstCustomersScreen> {
  List<InstCustomerRow> _all = const [];
  bool _loaded = false;
  String _q = '';
  late bool _noGuarantor = widget.onlyWithoutGuarantor;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await InstRepository.instance.listCustomers();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loaded = true;
    });
  }

  Future<void> _add() async {
    final id = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => const InstCustomerFormScreen()));
    await _reload();
    if (id != null && mounted) await _open(id);
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstCustomerDetailScreen(customerId: id)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final list = _all.where((r) {
      if (_noGuarantor && (r.profile == null || r.guarantorCount > 0)) return false;
      return r.matches(_q);
    }).toList();
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.teal,
        foregroundColor: Colors.white,
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(Loc.t('New Customer', 'نیا کسٹمر')),
      ),
      body: Column(children: [
        instHeader(context, p, Loc.t('Customers', 'کسٹمرز'), Loc.t('${_all.length} total', 'کل ${_all.length}')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: instDeco(p, Loc.t('Search name, phone or CNIC', 'نام، فون یا شناختی کارڈ سے تلاش'),
                suffix: const Icon(Icons.search)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            FilterChip(
              selected: _noGuarantor,
              label: Text(Loc.t('No guarantor', 'ضامن نہیں')),
              onSelected: (v) => setState(() => _noGuarantor = v),
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
                              ? Loc.t('No customers yet. Tap "New Customer".', 'ابھی کوئی کسٹمر نہیں۔ "نیا کسٹمر" دبائیں۔')
                              : Loc.t('Nothing found.', 'کچھ نہیں ملا۔'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.textMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _tile(p, list[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _tile(AppPalette p, InstCustomerRow r) {
    final prof = r.profile;
    final sub = <String>[
      if (prof != null && prof.fatherName.isNotEmpty) '${Loc.t('s/o', 'ولد')} ${prof.fatherName}',
      if (r.phone.isNotEmpty) r.phone,
      if (prof != null && prof.cnic.isNotEmpty) prof.cnic,
      if (prof != null && prof.khataNo.isNotEmpty) '${Loc.t('Khata', 'کھاتہ')} ${prof.khataNo}',
    ].join('  •  ');
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(r.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: instCard(p),
        child: Row(children: [
          PartyAvatar(isCustomer: true, partyId: r.id, name: r.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15.5)),
              if (sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 12)),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          if (prof != null && prof.isBlocked)
            _badge(p, Loc.t('Blacklist', 'بلیک لسٹ'), p.red)
          else if (prof == null)
            _badge(p, Loc.t('No CNIC', 'کارڈ نہیں'), p.textMuted)
          else if (r.guarantorCount == 0)
            _badge(p, Loc.t('No guarantor', 'ضامن نہیں'), p.red)
          else
            _badge(p, Loc.t('${r.guarantorCount} guarantor', '${r.guarantorCount} ضامن'), p.teal),
        ]),
      ),
    );
  }

  Widget _badge(AppPalette p, String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
      );
}

// ===================================================================== form

/// Naya ya purana customer. Save par customer id wapas (pop).
class InstCustomerFormScreen extends StatefulWidget {
  final Customer? existing;
  final CustomerProfile? profile;
  const InstCustomerFormScreen({super.key, this.existing, this.profile});

  @override
  State<InstCustomerFormScreen> createState() => _InstCustomerFormScreenState();
}

class _InstCustomerFormScreenState extends State<InstCustomerFormScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _father = TextEditingController(text: widget.profile?.fatherName ?? '');
  late final _cnic = TextEditingController(text: widget.profile?.cnic ?? '');
  late final _khata = TextEditingController(text: widget.profile?.khataNo ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _phone2 = TextEditingController(text: widget.profile?.phone2 ?? '');
  late final _address = TextEditingController(text: widget.profile?.address ?? '');
  late final _occupation = TextEditingController(text: widget.profile?.occupation ?? '');
  late final _workAddress = TextEditingController(text: widget.profile?.workAddress ?? '');
  late final _income = TextEditingController(
      text: (widget.profile?.monthlyIncome ?? 0) > 0 ? instPlain(widget.profile!.monthlyIncome) : '');
  late final _note = TextEditingController(text: widget.profile?.note ?? '');
  bool _saving = false;
  PhotoSlot _face = PhotoSlot();
  PhotoSlot _cnicF = PhotoSlot();
  PhotoSlot _cnicB = PhotoSlot();

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final id = widget.existing?.id;
    if (id == null) return;
    await PartyPhotoStore.instance.ensureLoaded();
    await KycPhotoStore.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _face = PhotoSlot(PartyPhotoStore.instance.pathFor(true, id));
      _cnicF = PhotoSlot(KycPhotoStore.instance.pathFor('c', id, KycPhotoStore.cnicFront));
      _cnicB = PhotoSlot(KycPhotoStore.instance.pathFor('c', id, KycPhotoStore.cnicBack));
    });
  }

  /// Customer save hone ke baad (id ab pata hai) tasveerein. Tasveer fail ho to customer phir bhi save rahe.
  Future<void> _savePhotos(int id) async {
    try {
      if (_face.newPath != null) {
        await PartyPhotoStore.instance.saveFrom(_face.newPath!, customer: true, id: id);
      } else if (_face.removed) {
        await PartyPhotoStore.instance.remove(customer: true, id: id);
      }
      for (final (slot, kind) in [(_cnicF, KycPhotoStore.cnicFront), (_cnicB, KycPhotoStore.cnicBack)]) {
        if (slot.newPath != null) {
          await KycPhotoStore.instance.saveFrom(slot.newPath!, owner: 'c', id: id, kind: kind);
        } else if (slot.removed) {
          await KycPhotoStore.instance.remove(owner: 'c', id: id, kind: kind);
        }
      }
    } catch (_) {
      if (mounted) instToast(context, Loc.t('Customer saved, but a photo could not be saved.', 'کسٹمر محفوظ ہو گیا، مگر تصویر محفوظ نہ ہو سکی۔'));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _father, _cnic, _khata, _phone, _phone2, _address, _occupation, _workAddress, _income, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final prof = CustomerProfile(
      customerId: widget.existing?.id ?? 0,
      fatherName: _father.text,
      cnic: _cnic.text,
      khataNo: _khata.text,
      phone2: _phone2.text,
      address: _address.text,
      occupation: _occupation.text,
      workAddress: _workAddress.text,
      monthlyIncome: instParse(_income.text),
      note: _note.text,
    );
    try {
      final int id;
      if (widget.existing == null) {
        id = await InstRepository.instance.addCustomer(name: _name.text, phone: _phone.text, profile: prof);
      } else {
        await InstRepository.instance.updateCustomer(widget.existing!, name: _name.text, phone: _phone.text, profile: prof);
        id = widget.existing!.id!;
      }
      await _savePhotos(id);
      if (mounted) Navigator.of(context).pop(id);
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
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(
          context,
          p,
          widget.existing == null ? Loc.t('New Customer', 'نیا کسٹمر') : Loc.t('Edit Customer', 'کسٹمر میں تبدیلی'),
          Loc.t('Only the name is required', 'صرف نام لازمی ہے'),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            instSectionTitle(p, Loc.t('PHOTOS', 'تصویریں')),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: instCard(p),
              child: Wrap(alignment: WrapAlignment.spaceEvenly, spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
                PhotoSlotBox(slot: _face, label: Loc.t('Customer snap', 'کسٹمر کی تصویر'), round: true, size: 104),
                PhotoSlotBox(slot: _cnicF, label: Loc.t('CNIC front', 'کارڈ سامنے')),
                PhotoSlotBox(slot: _cnicB, label: Loc.t('CNIC back', 'کارڈ پیچھے')),
              ]),
            ),
            instSectionTitle(p, Loc.t('PERSONAL', 'ذاتی معلومات')),
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: instDeco(p, Loc.t('Name *', 'نام *'))),
            gap(),
            TextField(controller: _father, textCapitalization: TextCapitalization.words, decoration: instDeco(p, Loc.t('Father / husband name', 'والد / شوہر کا نام'))),
            gap(),
            TextField(
              controller: _cnic,
              keyboardType: TextInputType.number,
              inputFormatters: [CnicInputFormatter()],
              decoration: instDeco(p, Loc.t('CNIC', 'شناختی کارڈ نمبر'), hint: '35202-1234567-1'),
            ),
            gap(),
            TextField(
              controller: _khata,
              decoration: instDeco(p, Loc.t('Register khata no.', 'رجسٹر کھاتہ نمبر'), hint: Loc.t('optional', 'اختیاری')),
            ),
            instSectionTitle(p, Loc.t('CONTACT', 'رابطہ')),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: instDeco(p, Loc.t('Phone', 'فون'), hint: '03xx xxxxxxx')),
            gap(),
            TextField(controller: _phone2, keyboardType: TextInputType.phone, decoration: instDeco(p, Loc.t('Second phone', 'دوسرا فون'))),
            gap(),
            TextField(controller: _address, maxLines: 2, decoration: instDeco(p, Loc.t('Home address', 'گھر کا پتہ'))),
            instSectionTitle(p, Loc.t('WORK', 'کام / روزگار')),
            TextField(controller: _occupation, decoration: instDeco(p, Loc.t('Job / business', 'نوکری / کاروبار'))),
            gap(),
            TextField(controller: _workAddress, maxLines: 2, decoration: instDeco(p, Loc.t('Work address', 'کام کی جگہ کا پتہ'))),
            gap(),
            TextField(
              controller: _income,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: instDeco(p, Loc.t('Monthly income (approx.)', 'ماہانہ آمدنی (اندازاً)')),
            ),
            gap(),
            TextField(controller: _note, maxLines: 2, decoration: instDeco(p, Loc.t('Note', 'نوٹ'))),
            const SizedBox(height: 20),
            instPrimaryButton(p, _saving ? Loc.t('Saving...', 'محفوظ ہو رہا ہے...') : Loc.t('Save', 'محفوظ کریں'), _saving ? null : _save),
          ]),
        ),
      ]),
    );
  }
}

// ===================================================================== detail

class InstCustomerDetailScreen extends StatefulWidget {
  final int customerId;
  const InstCustomerDetailScreen({super.key, required this.customerId});

  @override
  State<InstCustomerDetailScreen> createState() => _InstCustomerDetailScreenState();
}

class _InstCustomerDetailScreenState extends State<InstCustomerDetailScreen> {
  Customer? _c;
  CustomerProfile? _p;
  List<Guarantor> _g = const [];
  List<PlanView> _plans = const [];
  List<CashSaleView> _cashBuys = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    KycPhotoStore.instance.changes.addListener(_repaint);
    _reload();
  }

  @override
  void dispose() {
    KycPhotoStore.instance.changes.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final repo = InstRepository.instance;
    final c = await repo.customer(widget.customerId);
    final p = await repo.profile(widget.customerId);
    final g = await repo.guarantors(widget.customerId);
    final plans = await InstPlanRepository.instance.list(customerId: widget.customerId);
    final cashBuys = await InstCashSaleRepository.instance.list(customerId: widget.customerId);
    await KycPhotoStore.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _c = c;
      _p = p;
      _g = g;
      _plans = plans;
      _cashBuys = cashBuys;
      _loaded = true;
    });
  }

  Future<void> _edit() async {
    final c = _c;
    if (c == null) return;
    await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => InstCustomerFormScreen(existing: c, profile: _p)));
    await _reload();
  }

  Future<void> _editGuarantor([Guarantor? g]) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InstGuarantorFormScreen(customerId: widget.customerId, existing: g)));
    await _reload();
  }

  Future<void> _deleteGuarantor(Guarantor g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('Remove guarantor?', 'ضامن ہٹائیں؟')),
        content: Text(g.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Remove', 'ہٹائیں'))),
        ],
      ),
    );
    if (ok != true || g.id == null) return;
    // Tasveerein pehle (cloud se hatane ke liye guarantor ki serverId abhi chahiye), phir guarantor.
    await KycPhotoStore.instance.removeAll(owner: 'g', id: g.id!);
    await InstRepository.instance.deleteGuarantor(g.id!);
    await _reload();
  }

  /// Blacklist lagao / hatao (admin / manager).
  Future<void> _toggleBlock() async {
    final blocked = _p?.isBlocked ?? false;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(blocked ? Loc.t('Remove from blacklist?', 'بلیک لسٹ سے ہٹائیں؟') : Loc.t('Blacklist customer', 'کسٹمر بلیک لسٹ کریں')),
        content: blocked
            ? Text('${Loc.t('Reason', 'وجہ')}: ${_p!.blockedReason}')
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(Loc.t('A new installment for this customer will need Admin / Manager approval.',
                    'اس کسٹمر کی نئی قسط صرف ایڈمن / مینیجر کی اجازت سے بنے گی۔')),
                const SizedBox(height: 10),
                TextField(
                    controller: reason,
                    autofocus: true,
                    decoration: InputDecoration(hintText: Loc.t('Reason (e.g. stopped paying)', 'وجہ (مثلاً قسط بند کر دی)'))),
              ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(blocked ? Loc.t('Remove', 'ہٹائیں') : Loc.t('Blacklist', 'بلیک لسٹ'))),
        ],
      ),
    );
    if (ok != true) return;
    final text = blocked ? '' : reason.text.trim();
    if (!blocked && text.isEmpty) {
      if (mounted) instToast(context, Loc.t('Write a reason.', 'وجہ لکھیں۔'));
      return;
    }
    try {
      await InstRepository.instance.setBlocked(widget.customerId, text);
      await _reload();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  /// Customer ki poori history (Step 30): kitne plan (chalte / mukammal / wapas), kul kharida, kul diya, baqi, late.
  /// Ek bande ke kai plan isi screen par neeche ek saath.
  Widget _historyCard(AppPalette p) {
    final active = _plans.where((v) => v.plan.status == planActive).toList();
    final done = _plans.where((v) => v.plan.status == planCompleted).length;
    final back = _plans.where((v) => v.plan.status == planRepossessed).length;
    final bought = _plans.fold<double>(0, (a, v) => a + v.plan.totalPrice);
    final paid = _plans.fold<double>(0, (a, v) => a + v.advancePaid + v.status.paid);
    final left = active.fold<double>(0, (a, v) => a + v.status.remaining);
    final late = active.where((v) => v.status.overdue > 0.5).length;
    Widget cell(String label, String value, Color c) => Expanded(
          child: Column(children: [
            Text(value, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 11)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: instCard(p),
      child: Column(children: [
        Row(children: [
          cell(Loc.t('Running', 'جاری'), '${active.length}', p.navy),
          cell(Loc.t('Completed', 'مکمل'), '$done', p.teal),
          cell(Loc.t('Taken back', 'واپس لیا'), '$back', back > 0 ? p.red : p.textMuted),
          cell(Loc.t('Late now', 'ابھی لیٹ'), '$late', late > 0 ? p.red : p.textMuted),
        ]),
        const Divider(),
        Row(children: [
          cell(Loc.t('Total bought', 'کل خریدا'), instRs(bought), p.textDark),
          cell(Loc.t('Total paid', 'کل ادا'), instRs(paid), p.teal),
          cell(Loc.t('Remaining', 'باقی'), instRs(left), left > 0.5 ? p.amber : p.teal),
        ]),
      ]),
    );
  }

  Future<void> _call(String phone) async {
    final d = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (d.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: d));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final c = _c;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(
          context,
          p,
          c?.name ?? Loc.t('Customer', 'کسٹمر'),
          _p == null || _p!.fatherName.isEmpty ? '' : '${Loc.t('s/o', 'ولد')} ${_p!.fatherName}',
          actions: [
            if (c != null && Session.isAdminOrManager)
              IconButton(
                  tooltip: Loc.t('Blacklist', 'بلیک لسٹ'),
                  icon: Icon((_p?.isBlocked ?? false) ? Icons.lock_open : Icons.block, color: Colors.white),
                  onPressed: _toggleBlock),
            if (c != null)
              IconButton(tooltip: Loc.t('Edit', 'تبدیلی'), icon: const Icon(Icons.edit_outlined, color: Colors.white), onPressed: _edit),
          ],
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : c == null
                  ? Center(child: Text(Loc.t('Customer not found.', 'کسٹمر نہیں ملا۔'), style: TextStyle(color: p.textMuted)))
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
                      if (_p?.isBlocked ?? false)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: p.red.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            Icon(Icons.block, color: p.red),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('${Loc.t('BLACKLISTED', 'بلیک لسٹ')}: ${_p!.blockedReason}',
                                  style: TextStyle(color: p.red, fontWeight: FontWeight.bold)),
                            ),
                          ]),
                        ),
                      _profileCard(p, c),
                      const SizedBox(height: 12),
                      if (c.phone.isNotEmpty)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.call_outlined),
                          label: Text(Loc.t('Call', 'کال')),
                          onPressed: () => _call(c.phone),
                        ),
                      instSectionTitle(p, Loc.t('INSTALLMENT PLANS', 'قسط پلان')),
                      if (_plans.isNotEmpty) _historyCard(p),
                      for (final v in _plans)
                        PlanTile(
                          view: v,
                          showCustomer: false,
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InstPlanDetailScreen(planId: v.plan.id)));
                            await _reload();
                          },
                        ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: p.teal, minimumSize: const Size.fromHeight(46)),
                        icon: const Icon(Icons.add_card),
                        label: Text(Loc.t('New installment for this customer', 'اس کسٹمر کی نئی قسط')),
                        onPressed: () async {
                          await Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => NewInstallmentScreen(customerId: widget.customerId)));
                          await _reload();
                        },
                      ),
                      if (_cashBuys.isNotEmpty) ...[
                        instSectionTitle(p, Loc.t('CASH PURCHASES', 'نقد خریداری')),
                        for (final v in _cashBuys)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: instCard(p),
                            child: ListTile(
                              onTap: () async {
                                await Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => InstCashSaleDetailScreen(saleId: v.sale.id)));
                                await _reload();
                              },
                              leading: Icon(Icons.payments_outlined, color: p.teal),
                              title: Text(v.itemTitle, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                              subtitle: Text(v.sale.saleNo, style: TextStyle(color: p.textMuted, fontSize: 12)),
                              trailing: Text(instRs(v.sale.price), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                      instSectionTitle(p, Loc.t('DOCUMENTS', 'کاغذات')),
                      KycPhotoRow(owner: 'c', id: c.id!, kinds: const [
                        KycPhotoStore.cnicFront,
                        KycPhotoStore.cnicBack,
                        KycPhotoStore.document,
                      ]),
                      instSectionTitle(p, Loc.t('GUARANTORS', 'ضامن')),
                      if (_g.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: instCard(p),
                          child: Row(children: [
                            Icon(Icons.warning_amber_rounded, color: p.red),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(Loc.t('No guarantor yet. Big items (bike, AC) need 2.', 'ابھی کوئی ضامن نہیں۔ بڑی چیز (بائیک، اے سی) کے لیے 2 ضامن۔'),
                                  style: TextStyle(color: p.textDark)),
                            ),
                          ]),
                        ),
                      for (final g in _g) _guarantorCard(p, g),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.person_add_alt),
                        label: Text(Loc.t('Add guarantor', 'ضامن شامل کریں')),
                        onPressed: () => _editGuarantor(),
                      ),
                    ]),
        ),
      ]),
    );
  }

  Widget _profileCard(AppPalette p, Customer c) {
    final pr = _p;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: instCard(p, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PartyAvatar(
            isCustomer: true,
            partyId: c.id,
            name: c.name,
            radius: 30,
            onTap: () => showPartyPhotoSheet(context, isCustomer: true, partyId: c.id!),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 18)),
              if (pr != null && pr.cnic.isNotEmpty)
                Text(pr.cnic, style: TextStyle(color: p.textMuted, fontSize: 13, letterSpacing: 0.5)),
              Text(Loc.t('Tap photo to change', 'تصویر بدلنے کے لیے دبائیں'), style: TextStyle(color: p.textMuted, fontSize: 10.5)),
            ]),
          ),
        ]),
        const Divider(height: 24),
        instInfoLine(p, Loc.t('Phone', 'فون'), c.phone),
        if (pr != null) ...[
          instInfoLine(p, Loc.t('Khata no.', 'کھاتہ نمبر'), pr.khataNo),
          instInfoLine(p, Loc.t('Second phone', 'دوسرا فون'), pr.phone2),
          instInfoLine(p, Loc.t('Address', 'پتہ'), pr.address),
          instInfoLine(p, Loc.t('Job / business', 'روزگار'), pr.occupation),
          instInfoLine(p, Loc.t('Work address', 'کام کا پتہ'), pr.workAddress),
          instInfoLine(p, Loc.t('Monthly income', 'ماہانہ آمدنی'), pr.monthlyIncome > 0 ? instRs(pr.monthlyIncome) : ''),
          instInfoLine(p, Loc.t('Note', 'نوٹ'), pr.note),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.badge_outlined),
              label: Text(Loc.t('Add CNIC, address and work details', 'شناختی کارڈ، پتہ اور روزگار درج کریں')),
            ),
          ),
      ]),
    );
  }

  Widget _guarantorCard(AppPalette p, Guarantor g) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: instCard(p),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (g.id != null) ...[
              KycAvatar(owner: 'g', id: g.id!, name: g.name, radius: 24),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15.5)),
                Text(
                  [
                    if (g.fatherName.isNotEmpty) '${Loc.t('s/o', 'ولد')} ${g.fatherName}',
                    if (g.relation.isNotEmpty) g.relation,
                  ].join('  •  '),
                  style: TextStyle(color: p.textMuted, fontSize: 12),
                ),
              ]),
            ),
            if (g.phone.isNotEmpty)
              IconButton(icon: Icon(Icons.call_outlined, color: p.teal), onPressed: () => _call(g.phone)),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? _editGuarantor(g) : _deleteGuarantor(g),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(Loc.t('Edit', 'تبدیلی'))),
                PopupMenuItem(value: 'delete', child: Text(Loc.t('Remove', 'ہٹائیں'))),
              ],
            ),
          ]),
          const SizedBox(height: 6),
          instInfoLine(p, Loc.t('CNIC', 'شناختی کارڈ'), g.cnic),
          instInfoLine(p, Loc.t('Phone', 'فون'), g.phone),
          instInfoLine(p, Loc.t('Address', 'پتہ'), g.address),
          instInfoLine(p, Loc.t('Job / business', 'روزگار'), g.occupation),
          if (g.id != null) ...[
            const SizedBox(height: 6),
            KycPhotoRow(owner: 'g', id: g.id!, kinds: const [KycPhotoStore.cnicFront, KycPhotoStore.cnicBack]),
          ],
        ]),
      );
}

// ===================================================================== guarantor form

class InstGuarantorFormScreen extends StatefulWidget {
  final int customerId;
  final Guarantor? existing;
  const InstGuarantorFormScreen({super.key, required this.customerId, this.existing});

  @override
  State<InstGuarantorFormScreen> createState() => _InstGuarantorFormScreenState();
}

class _InstGuarantorFormScreenState extends State<InstGuarantorFormScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _father = TextEditingController(text: widget.existing?.fatherName ?? '');
  late final _cnic = TextEditingController(text: widget.existing?.cnic ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _relation = TextEditingController(text: widget.existing?.relation ?? '');
  late final _occupation = TextEditingController(text: widget.existing?.occupation ?? '');
  bool _saving = false;
  PhotoSlot _photo = PhotoSlot();
  PhotoSlot _cnicF = PhotoSlot();
  PhotoSlot _cnicB = PhotoSlot();

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final st = KycPhotoStore.instance;
    await st.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _photo = PhotoSlot(st.pathFor('g', id, KycPhotoStore.photo));
      _cnicF = PhotoSlot(st.pathFor('g', id, KycPhotoStore.cnicFront));
      _cnicB = PhotoSlot(st.pathFor('g', id, KycPhotoStore.cnicBack));
    });
  }

  Future<void> _savePhotos(int id) async {
    try {
      for (final (slot, kind) in [(_photo, KycPhotoStore.photo), (_cnicF, KycPhotoStore.cnicFront), (_cnicB, KycPhotoStore.cnicBack)]) {
        if (slot.newPath != null) {
          await KycPhotoStore.instance.saveFrom(slot.newPath!, owner: 'g', id: id, kind: kind);
        } else if (slot.removed) {
          await KycPhotoStore.instance.remove(owner: 'g', id: id, kind: kind);
        }
      }
    } catch (_) {
      if (mounted) instToast(context, Loc.t('Guarantor saved, but a photo could not be saved.', 'ضامن محفوظ ہو گیا، مگر تصویر محفوظ نہ ہو سکی۔'));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _father, _cnic, _phone, _address, _relation, _occupation]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Ye banda pehle se kitno ka zamin hai? Warning (rokta nahi).
      final others = await InstRepository.instance.guaranteesByCnic(_cnic.text, exceptGuarantorId: widget.existing?.id);
      if (others.isNotEmpty && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(Loc.t('Already a guarantor', 'پہلے سے ضامن ہے')),
            content: Text(Loc.t('This CNIC is already guarantor for: ${others.join(', ')}. Continue?',
                'یہ شناختی کارڈ پہلے سے ان کا ضامن ہے: ${others.join('، ')}۔ پھر بھی محفوظ کریں؟')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Save anyway', 'پھر بھی محفوظ'))),
            ],
          ),
        );
        if (go != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
      final gid = await InstRepository.instance.saveGuarantor(Guarantor(
        id: widget.existing?.id,
        customerId: widget.customerId,
        name: _name.text,
        fatherName: _father.text,
        cnic: _cnic.text,
        phone: _phone.text,
        address: _address.text,
        relation: _relation.text,
        occupation: _occupation.text,
        createdAt: widget.existing?.createdAt ?? 0,
      ));
      await _savePhotos(gid);
      if (mounted) Navigator.of(context).pop(gid);
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
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, widget.existing == null ? Loc.t('Add Guarantor', 'ضامن شامل کریں') : Loc.t('Edit Guarantor', 'ضامن میں تبدیلی'),
            Loc.t('Only the name is required', 'صرف نام لازمی ہے')),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: instCard(p),
              child: Wrap(alignment: WrapAlignment.spaceEvenly, spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
                PhotoSlotBox(slot: _photo, label: Loc.t('Guarantor photo', 'ضامن کی تصویر'), round: true, size: 104),
                PhotoSlotBox(slot: _cnicF, label: Loc.t('CNIC front', 'کارڈ سامنے')),
                PhotoSlotBox(slot: _cnicB, label: Loc.t('CNIC back', 'کارڈ پیچھے')),
              ]),
            ),
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: instDeco(p, Loc.t('Name *', 'نام *'))),
            gap(),
            TextField(controller: _father, textCapitalization: TextCapitalization.words, decoration: instDeco(p, Loc.t('Father name', 'والد کا نام'))),
            gap(),
            TextField(
              controller: _cnic,
              keyboardType: TextInputType.number,
              inputFormatters: [CnicInputFormatter()],
              decoration: instDeco(p, Loc.t('CNIC', 'شناختی کارڈ نمبر'), hint: '35202-1234567-1'),
            ),
            gap(),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: instDeco(p, Loc.t('Phone', 'فون'), hint: '03xx xxxxxxx')),
            gap(),
            TextField(controller: _relation, decoration: instDeco(p, Loc.t('Relation (brother, friend...)', 'رشتہ (بھائی، دوست...)'))),
            gap(),
            TextField(controller: _address, maxLines: 2, decoration: instDeco(p, Loc.t('Address', 'پتہ'))),
            gap(),
            TextField(controller: _occupation, decoration: instDeco(p, Loc.t('Job / business', 'نوکری / کاروبار'))),
            const SizedBox(height: 20),
            instPrimaryButton(p, _saving ? Loc.t('Saving...', 'محفوظ ہو رہا ہے...') : Loc.t('Save', 'محفوظ کریں'), _saving ? null : _save),
          ]),
        ),
      ]),
    );
  }
}

// ===================================================================== photos

String _kindLabel(String kind) => switch (kind) {
      KycPhotoStore.cnicFront => Loc.t('CNIC front', 'کارڈ سامنے'),
      KycPhotoStore.cnicBack => Loc.t('CNIC back', 'کارڈ پیچھے'),
      KycPhotoStore.photo => Loc.t('Photo', 'تصویر'),
      _ => Loc.t('Cheque / stamp', 'چیک / اسٹامپ'),
    };

/// CNIC aage / peeche / kaghaz ki chhoti tasveerein. Tap = badlein / dekhein / hatayein.
class KycPhotoRow extends StatelessWidget {
  final String owner;
  final int id;
  final List<String> kinds;
  const KycPhotoRow({super.key, required this.owner, required this.id, required this.kinds});

  Future<void> _tap(BuildContext context, String kind) async {
    final store = KycPhotoStore.instance;
    await store.ensureLoaded();
    if (!context.mounted) return;
    final path = store.pathFor(owner, id, kind);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (path != null)
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: Text(Loc.t('View', 'دیکھیں')),
              onTap: () => Navigator.pop(ctx, 'view'),
            ),
          if (KycPhotoStore.cameraAvailable)
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(Loc.t('Take photo', 'کیمرے سے تصویر')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(KycPhotoStore.cameraAvailable ? Loc.t('Choose from gallery', 'گیلری سے چنیں') : Loc.t('Choose file', 'فائل چنیں')),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (path != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(Loc.t('Remove', 'ہٹائیں')),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'view' && path != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(child: Image.file(File(path), fit: BoxFit.contain)),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (choice == 'remove') {
        await store.remove(owner: owner, id: id, kind: kind);
      } else {
        await store.pick(choice == 'camera' ? ImageSource.camera : ImageSource.gallery, owner: owner, id: id, kind: kind);
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(Loc.t('Photo could not be saved (check camera/photos permission)', 'تصویر محفوظ نہ ہو سکی (کیمرہ/فوٹو اجازت دیکھیں)'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final store = KycPhotoStore.instance;
    return ValueListenableBuilder<int>(
      valueListenable: store.changes,
      builder: (context, _, __) => Wrap(spacing: 10, runSpacing: 10, children: [
        for (final k in kinds)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _tap(context, k),
            child: Container(
              width: 100,
              height: 78,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: p.fieldFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              child: Stack(fit: StackFit.expand, children: [
                if (store.pathFor(owner, id, k) != null)
                  Image.file(File(store.pathFor(owner, id, k)!), fit: BoxFit.cover)
                else
                  Icon(Icons.add_a_photo_outlined, color: p.textMuted),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(_kindLabel(k),
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10.5)),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}


/// Naye qist plan se pehle (Step 18): blacklist / pehle saman wapas => warning. Blacklist customer ka plan
/// sirf Admin / Manager bana sakta hai. Wapas true = aage barhein.
Future<bool> instRiskCheck(BuildContext context, int customerId, {List<int> guarantorIds = const []}) async {
  final r = await InstRepository.instance.risk(customerId);
  final gIssues = await InstRepository.instance.guarantorRisks(guarantorIds);
  if ((r == null && gIssues.isEmpty) || !context.mounted) return true;
  final blocked = r?.blocked ?? false;
  final canGo = !blocked || Session.isAdminOrManager;
  final lines = [
    if (blocked) '${Loc.t('BLACKLISTED', 'بلیک لسٹ')}: ${r!.blockedReason}',
    if ((r?.repossessed ?? 0) > 0)
      Loc.t('Item was taken back ${r!.repossessed} time(s) before.', 'پہلے ${r!.repossessed} دفعہ سامان واپس لیا گیا۔'),
    for (final g in gIssues) '${Loc.t('Guarantor', 'ضامن')} — $g',
    if (!canGo) Loc.t('Only Admin / Manager can make a plan for this customer.', 'اس کسٹمر کا پلان صرف ایڈمن / مینیجر بنا سکتا ہے۔'),
  ];
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 36),
      title: Text(Loc.t('Risky customer', 'خطرناک کسٹمر')),
      content: Text(lines.map((e) => '•  $e').join('\n')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Go back', 'واپس'))),
        if (canGo) TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Continue anyway', 'پھر بھی جاری'))),
      ],
    ),
  );
  return go == true;
}
