import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../screens/cash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/settings_screen.dart';
import '../services/crash_handler.dart';
import '../services/crash_reporter.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_cash_sale_screens.dart';
import 'inst_collection_screens.dart';
import 'inst_customers_screen.dart';
import 'inst_items_screen.dart';
import 'inst_plan_repository.dart';
import 'inst_plans_screen.dart';
import 'inst_purchase_repository.dart';
import 'inst_purchase_screens.dart';
import 'inst_report_screens.dart';
import 'inst_home_search.dart';
import 'inst_scan.dart';
import 'inst_bulk_remind.dart';
import 'inst_security_screens.dart';
import 'inst_trend_chart.dart';
import 'inst_update.dart';
import 'inst_repository.dart';
import 'inst_shop_tools_screen.dart';
import '../license/license_screen.dart';
import '../services/bill_reminder_service.dart';
import '../services/staff_auth.dart';
import '../db/cash_repository.dart';
import '../db/user_repository.dart';
import '../sync/branch_config_store.dart';
import '../sync/settings_sync.dart';
import 'inst_ui.dart';

/// Hanna Installment ka home (login ke baad pehli screen).
///
/// Step 2 tak: Customers (CNIC + guarantor), Stock (har piece IMEI / engine no. ke saath), Categories.
/// Step 3: Nayi Qist, Qisten (aaj / late / jari), aaj ki wasooli. POS ki purani screens (cash, expense, reports...) abhi
/// "Shop tools" se khulti hain — pehli kamyab build ke baad ghair-zaroori hisse nikale jayenge.
class InstallmentHomeScreen extends StatefulWidget {
  const InstallmentHomeScreen({super.key});

  @override
  State<InstallmentHomeScreen> createState() => _InstallmentHomeScreenState();
}

class _InstallmentHomeScreenState extends State<InstallmentHomeScreen> {
  InstHomeStats _stats = const InstHomeStats();
  InstCollectionStats _col = const InstCollectionStats();
  bool _syncing = false;
  // Settings > Shop Information: dukaan ka naam / phone dashboard ke upar (khali = app ka naam).
  String _shopName = '';
  String _shopPhone = '';
  double _payable = 0; // Step 31: suppliers ka kul baqi (hum ne dena hai)
  bool _showMoney = false; // Step 32: Lena / Dena raqam chhupi; aankh dabane par

  /// Dashboard ka Sync button: abhi cloud se lena / dena (Settings > Sync Now jaisa).
  Future<void> _syncNow() async {
    if (_syncing) return;
    if (!await SettingsSync.cloudConfigured() || !BranchConfigStore.isConfigured()) {
      if (mounted) {
        instToast(context, Loc.t('Cloud sync is not set up. Settings > Cloud Sync.', 'کلاؤڈ سنک سیٹ نہیں۔ سیٹنگز > کلاؤڈ سنک۔'));
      }
      return;
    }
    if (!await SettingsSync.isOnline()) {
      if (mounted) instToast(context, Loc.t('No internet connection', 'انٹرنیٹ کنکشن نہیں'));
      return;
    }
    setState(() => _syncing = true);
    String? msg;
    try {
      msg = await SettingsSync.syncNow();
    } catch (e) {
      msg = Loc.t('Sync failed', 'سنک ناکام');
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    instToast(context, msg ?? Loc.t('No internet connection', 'انٹرنیٹ کنکشن نہیں'));
    await _load();
  }

  @override
  void initState() {
    super.initState();
    InstRepository.instance.changes.addListener(_load);
    _load();
    // "Secure Cloud Login (staff)" Settings se hata diya (staff server set nahi). Pehle ON kiya ho to OFF — warna
    // sync anonymous par wapas nahi jata aur ruk jata hai.
    StaffAuth.isEnabled().then((on) {
      if (on) StaffAuth.setEnabled(false);
    });
    // Android 13+: roz ki qist notification ke liye ijazat (pehli baar poochta hai).
    BillReminderService.requestPermission();
    // Pichhli dafa app band (crash) hui ho to log dikhao / developer ko bhejo (purane POS dashboard se).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLastCrash());
    // Naya update (har 6 ghante mein ek dafa, internet ho to).
    WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(seconds: 4), () {
          if (mounted) InstUpdate.checkOnStart(context);
        }));
  }

  /// Kotlin `showCrashDialog`: pichli baar crash hui ho to log dikhao (Share / Copy / Dismiss).
  Future<void> _checkLastCrash() async {
    final text = await CrashHandler.getLastCrash();
    if (text == null || !mounted) return;
    // Cloud Sync juda ho to developer ko khud (Firestore crash_reports) — dialog ka intezar kiye baghair.
    CrashReporter.uploadIfNew(text).ignore();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('App crashed last time', 'پچھلی بار ایپ کریش ہوئی تھی')),
        content: SingleChildScrollView(
          child: SelectableText(CrashHandler.preview(text), style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await launchUrl(CrashReporter.whatsAppUri(text), mode: LaunchMode.externalApplication);
              } catch (_) {}
              await CrashHandler.clearLastCrash();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(Loc.t('Send to developer', 'ڈیولپر کو بھیجیں')),
          ),
          TextButton(
            onPressed: () async {
              await Share.share(text, subject: 'Hanna Installment Crash Log');
              await CrashHandler.clearLastCrash();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(Loc.t('Share', 'شیئر کریں')),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(Loc.t('Copied', 'کاپی ہو گیا'))),
                );
              }
            },
            child: Text(Loc.t('Copy', 'کاپی')),
          ),
          TextButton(
            onPressed: () async {
              await CrashHandler.clearLastCrash();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(Loc.t('Dismiss', 'برخاست کریں')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    InstRepository.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await InstRepository.instance.homeStats();
      final c = await InstPlanRepository.instance.collectionStats();
      var payable = 0.0;
      try {
        payable = (await InstPurchaseRepository.instance.summary(from: 0, to: DateTime.now().millisecondsSinceEpoch + 1)).payable;
      } catch (_) {}
      final name = (await UserRepository.instance.getSetting('shop_name'))?.trim() ?? '';
      final phone = (await UserRepository.instance.getSetting('shop_phone'))?.trim() ?? '';
      if (mounted) {
        setState(() {
          _stats = s;
          _col = c;
          _shopName = name;
          _shopPhone = phone;
          _payable = payable;
        });
      }
    } catch (_) {}
  }

  /// Dashboard se ek jagah: paise aana (qist, naqd sale, cash in) aur jana (supplier, kharcha, cash out).
  Future<void> _payReceive() async {
    final p = ThemeManager.palette;
    final mgr = Session.isAdminOrManager;
    Widget item(IconData icon, Color color, String title, String sub, Widget screen) => ListTile(
          leading: CircleAvatar(backgroundColor: color.withOpacity(0.14), child: Icon(icon, color: color)),
          title: Text(title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
          subtitle: Text(sub, style: TextStyle(color: p.textMuted, fontSize: 12)),
          trailing: Icon(Icons.chevron_right, color: p.textMuted),
          onTap: () {
            Navigator.of(context).pop();
            _push(screen);
          },
        );
    Widget head(String t, Color c) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
        );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: p.bg,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Step 31: sirf 4 kaam — qist lena, doosra paisa aaya, supplier ko dena, kharcha / paisa gaya.
            head(Loc.t('RECEIVE (MONEY IN)', 'لینا (رقم آئی)'), p.teal),
            item(Icons.request_quote_outlined, p.teal, Loc.t('Installment collection', 'قسط کی وصولی'),
                Loc.t('Pick the customer, then Receive', 'کسٹمر چنیں، پھر وصول کریں'), const InstCollectionListScreen()),
            ListTile(
              leading: CircleAvatar(backgroundColor: p.blue.withOpacity(0.14), child: Icon(Icons.south_west, color: p.blue)),
              title: Text(Loc.t('Other money in', 'دوسری رقم آئی'), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
              subtitle: Text(Loc.t('Amount + reason, done', 'رقم + وجہ، بس'), style: TextStyle(color: p.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.of(ctx).pop();
                _quickCash('IN');
              },
            ),
            head(Loc.t('PAY (MONEY OUT)', 'دینا (رقم گئی)'), p.red),
            if (mgr)
              item(Icons.local_shipping_outlined, p.red, Loc.t('Pay supplier', 'سپلائر کو ادائیگی'),
                  Loc.t('Choose supplier, then Pay', 'سپلائر چنیں، پھر ادا کریں'), const InstSuppliersScreen()),
            ListTile(
              leading: CircleAvatar(backgroundColor: p.orange.withOpacity(0.14), child: Icon(Icons.north_east, color: p.orange)),
              title: Text(Loc.t('Expense / other money out', 'خرچہ / دوسری رقم گئی'), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
              subtitle: Text(Loc.t('Amount + reason, done', 'رقم + وجہ، بس'), style: TextStyle(color: p.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.of(ctx).pop();
                _quickCash('OUT');
              },
            ),
            const Divider(),
            item(Icons.account_balance_wallet_outlined, p.navy, Loc.t('Cash book (all entries)', 'کیش بک (سب اندراج)'),
                Loc.t('Today in / out, edit', 'آج آیا / گیا'), const CashScreen()),
          ]),
        ),
      ),
    );
  }

  /// Seedha paisa aaya / gaya (Step 31): raqam, Cash / Bank, wajah — ek dialog, cash book mein darj.
  Future<void> _quickCash(String type) async {
    final p = ThemeManager.palette;
    final inn = type == 'IN';
    final amount = TextEditingController();
    final note = TextEditingController();
    var method = 'cash';
    var expense = true; // OUT: kharcha (munafe se kam) ya sirf paisa nikla (transfer)
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(inn ? Loc.t('Money in', 'رقم آئی') : Loc.t('Money out', 'رقم گئی')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: instDeco(p, Loc.t('Amount', 'رقم')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: instDeco(p, inn ? Loc.t('From whom / why', 'کس سے / کیوں') : Loc.t('To whom / why', 'کس کو / کیوں')),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'cash', label: Text(Loc.t('Cash', 'کیش'))),
                  ButtonSegment(value: 'bank', label: Text(Loc.t('Bank', 'بینک'))),
                ],
                selected: {method},
                onSelectionChanged: (v) => set(() => method = v.first),
              ),
              if (!inn) ...[
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: expense,
                  onChanged: (v) => set(() => expense = v),
                  title: Text(Loc.t('Shop expense', 'دکان کا خرچہ')),
                  subtitle: Text(expense
                      ? Loc.t('Bill, rent, tea... (reduces profit)', 'بل، کرایہ، چائے... (منافع سے کم)')
                      : Loc.t('Only moved (bank, owner...)', 'صرف منتقل (بینک، مالک...)')),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Save', 'محفوظ کریں'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = instParse(amount.text);
    if (amt <= 0) {
      if (mounted) instToast(context, Loc.t('Enter a valid amount', 'صحیح رقم لکھیں'));
      return;
    }
    try {
      await CashRepository.instance.save(
        type: type,
        amount: amt,
        method: method,
        category: inn ? CashCategories.otherIncome : (expense ? CashCategories.miscellaneous : CashCategories.nonExpense),
        note: note.text.trim(),
      );
      if (mounted) instToast(context, Loc.t('Saved', 'محفوظ ہو گیا'));
      await _load();
    } catch (e) {
      if (mounted) instToast(context, instErr(e));
    }
  }

  /// Returns (Step 31): sale wapsi / purchase wapsi / qist ka saman wapas — kahan se karna hai.
  Future<void> _returns() async {
    final p = ThemeManager.palette;
    final mgr = Session.isAdminOrManager;
    Widget item(IconData icon, Color color, String title, String sub, Widget screen) => ListTile(
          leading: CircleAvatar(backgroundColor: color.withOpacity(0.14), child: Icon(icon, color: color)),
          title: Text(title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
          subtitle: Text(sub, style: TextStyle(color: p.textMuted, fontSize: 12)),
          trailing: Icon(Icons.chevron_right, color: p.textMuted),
          onTap: () {
            Navigator.of(context).pop();
            _push(screen);
          },
        );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: p.bg,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          item(Icons.assignment_return_outlined, p.orange, Loc.t('Sale return (cash sale)', 'سیل واپسی (نقد سیل)'),
              Loc.t('Open the sale, then "Sale return"', 'سیل کھولیں، پھر "سیل واپسی"'), const InstCashSalesScreen()),
          if (mgr)
            item(Icons.undo, p.red, Loc.t('Installment item taken back', 'قسط کا سامان واپس'),
                Loc.t('Open the plan, ⋮ menu > "Take item back"', 'پلان کھولیں، ⋮ مینو > "سامان واپس لیں"'), const InstPlansScreen()),
          if (mgr)
            item(Icons.keyboard_return, p.navy, Loc.t('Purchase return (supplier)', 'خریداری واپسی (سپلائر)'),
                Loc.t('Open the bill, then "Return"', 'بل کھولیں، پھر "واپس کریں"'), const InstPurchasesScreen()),
          if (mgr)
            item(Icons.history, p.textMuted, Loc.t('Returns history', 'واپسی کی ہسٹری'), Loc.t('All returns by date', 'سب واپسیاں تاریخ وار'),
                const InstReturnsReportScreen()),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// "More": baqi tiles neeche ki sheet mein.
  Future<void> _more(AppPalette p, List<_Tile> more) async {
    final t = await showModalBottomSheet<_Tile>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final x in more)
              ListTile(
                leading: Icon(x.icon, color: x.color),
                title: Text(x.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(x.subtitle),
                onTap: () => Navigator.pop(ctx, x),
              ),
          ]),
        ),
      ),
    );
    t?.onTap();
  }

  Future<void> _push(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    await _load();
  }

  Future<void> _logout() async {
    await Session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1000 ? 4 : (width >= 640 ? 3 : 2);
    // Step 30: 8 main tiles + "More" (baqi sab). Purchase + stock ek hi jagah (purchase se stock khud banta hai).
    final mgr = Session.isAdminOrManager;
    final tNew = _Tile(Icons.add_card, Loc.t('New Installment', 'نئی قسط'), Loc.t('Qist or cash sale', 'قسط یا نقد سیل'), p.teal,
        () => _push(const NewInstallmentScreen()));
    final tPayRec = _Tile(Icons.swap_vert_circle_outlined, Loc.t('Pay / Receive', 'لینا / دینا'), Loc.t('Collect, pay, returns', 'وصولی، ادائیگی، واپسی'), p.teal,
        _payReceive);
    final tCustomers = _Tile(Icons.people_alt_outlined, Loc.t('Customers', 'کسٹمرز'), Loc.t('All plans, history', 'سب پلان، ہسٹری'), p.purple,
        () => _push(const InstCustomersScreen()));
    final tPurchases = _Tile(Icons.local_shipping_outlined, Loc.t('Purchase / Stock', 'خریداری / اسٹاک'), Loc.t('Buy -> stock auto', 'خریداری سے اسٹاک خود'), p.tealDark,
        () => _push(const InstPurchasesScreen()));
    final tStock = _Tile(Icons.inventory_2_outlined, Loc.t('Stock', 'اسٹاک'), Loc.t('Mobiles, bikes, LCDs...', 'موبائل، بائیک، ایل سی ڈی'), p.blue,
        () => _push(const InstItemsScreen()));
    final tPlans = _Tile(Icons.request_quote_outlined, Loc.t('Installments', 'قسطیں'), Loc.t('${_col.activePlans} active plans', '${_col.activePlans} جاری پلان'), p.navy,
        () => _push(const InstPlansScreen()));
    final tScan = _Tile(Icons.qr_code_scanner, Loc.t('Scan & Sell', 'اسکین سے سیل'), Loc.t('Scan IMEI -> qist / cash', 'IMEI اسکین -> قسط / نقد'), p.purple,
        () => _push(const InstScanSaleScreen()));
    final tRemind = _Tile(Icons.send_to_mobile_outlined, Loc.t('Send Reminders', 'یاد دہانی بھیجیں'), Loc.t('WhatsApp to all due', 'سب کو واٹس ایپ'), p.teal,
        () => _push(const InstBulkRemindScreen()));
    final tCheques = _Tile(Icons.payments_outlined, Loc.t('Cheques & Docs', 'چیک اور کاغذات'), Loc.t('Security held by shop', 'دکان کے پاس ضمانت'), p.navyLight,
        () => _push(const InstHeldSecuritiesScreen()));
    final tReturns = _Tile(Icons.assignment_return_outlined, Loc.t('Returns', 'واپسی'), Loc.t('Sale / purchase return', 'سیل / خریداری واپسی'), p.orange,
        _returns);
    final tCollection = _Tile(Icons.format_list_numbered, Loc.t('Collection', 'وصولی'), Loc.t('Everyone who owes', 'جن سے لینا ہے'), p.blue,
        () => _push(const InstCollectionListScreen()));
    final more = <_Tile>[
      tPlans,
      _Tile(Icons.report_gmailerrorred_outlined, Loc.t('Defaulters', 'ڈیفالٹرز'), Loc.t('Late + guarantor phones', 'لیٹ + ضامن کے فون'), p.red,
          () => _push(const InstDefaultersScreen())),
      if (mgr) tStock,
      _Tile(Icons.point_of_sale, Loc.t('Cash Sales', 'نقد سیلز'), Loc.t('List, returns', 'لسٹ، واپسی'), p.tealDark,
          () => _push(const InstCashSalesScreen())),
      _Tile(Icons.category_outlined, Loc.t('Categories', 'کیٹیگریز'), Loc.t('IMEI / serial fields', 'IMEI / سیریل فیلڈز'), p.amber,
          () => _push(const InstCategoriesScreen())),
      _Tile(Icons.storefront_outlined, Loc.t('Shop tools', 'دکان کے ٹولز'), Loc.t('Cash, expenses, staff, backup', 'کیش، خرچے، اسٹاف، بیک اپ'), p.orange,
          () => _push(const InstShopToolsScreen())),
    ];
    final tiles = <_Tile>[
      tNew,
      tPayRec,
      tCustomers,
      mgr ? tPurchases : tStock,
      tCollection,
      if (kShowScan) tScan,
      tReturns,
      tRemind,
      tCheques,
      _Tile(Icons.apps, Loc.t('More', 'مزید'), Loc.t('All other options', 'باقی سب'), p.textMuted, () => _more(p, more)),
    ];
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(
          context,
          p,
          _shopName.isNotEmpty ? _shopName : AppInfo.appName,
          [
            '${Loc.t('Hello', 'السلام علیکم')}, ${Session.displayName.isNotEmpty ? Session.displayName : (Session.username ?? '')}',
            if (_shopPhone.isNotEmpty) _shopPhone,
          ].join('  •  '),
          back: false,
          // Settings ka button upar bayen (Admin / Manager) — grid ka tile hata diya.
          leading: Session.isAdminOrManager
              ? IconButton(
                  tooltip: Loc.t('Settings', 'سیٹنگز'),
                  icon: const Icon(Icons.settings_outlined, color: Colors.white),
                  onPressed: () => _push(const SettingsScreen()),
                )
              : null,
          actions: [
            if (kShowScan)
              IconButton(
                tooltip: Loc.t('Scan & Sell', 'اسکین سے سیل'),
                icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                onPressed: () => _push(const InstScanSaleScreen()),
              ),
            IconButton(
              tooltip: Loc.t('Sync now', 'ابھی سنک کریں'),
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Icon(Icons.sync, color: Colors.white),
            ),
            IconButton(
              tooltip: Loc.t('Log out', 'لاگ آؤٹ'),
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _logout,
            ),
          ],
        ),
        const LicenseBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
              // Step 32: sab se upar Lena / Dena (chhupa — aankh dabakar dekhein), phir search, phir aaj ki qisten.
              if (Session.isAdminOrManager) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  decoration: instCard(p),
                  child: Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _push(const InstReceivableScreen()),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(Loc.t('Receivable (to get)', 'لینا ہے'), style: TextStyle(color: p.textMuted, fontSize: 12)),
                          Text(_showMoney ? instRs(_col.receivable) : 'Rs ••••••',
                              style: TextStyle(color: p.teal, fontWeight: FontWeight.bold, fontSize: 18)),
                        ]),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _push(const InstSuppliersScreen()),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(Loc.t('Payable (to give)', 'دینا ہے'), style: TextStyle(color: p.textMuted, fontSize: 12)),
                          Text(_showMoney ? instRs(_payable) : 'Rs ••••••',
                              style: TextStyle(color: p.red, fontWeight: FontWeight.bold, fontSize: 18)),
                        ]),
                      ),
                    ),
                    IconButton(
                      tooltip: _showMoney ? Loc.t('Hide', 'چھپائیں') : Loc.t('Show', 'دکھائیں'),
                      icon: Icon(_showMoney ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: p.textMuted),
                      onPressed: () => setState(() => _showMoney = !_showMoney),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              const InstHomeSearch(),
              Row(children: [
                Expanded(
                  child: _tapStat(p, Loc.t('Due today', 'آج کی قسطیں'), instRs(_col.dueToday),
                      Loc.t('${_col.dueTodayCount} customers', '${_col.dueTodayCount} کسٹمر'), p.amber,
                      () => _push(const InstCollectionListScreen(initial: CollectWindow.today))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _tapStat(p, Loc.t('Late', 'لیٹ'), instRs(_col.overdue),
                      Loc.t('${_col.overdueCount} customers', '${_col.overdueCount} کسٹمر'), p.red,
                      () => _push(const InstDefaultersScreen(minDays: 1))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _tapStat(p, Loc.t('Collected', 'آج وصولی'), instRs(_col.collectedToday),
                      Loc.t('Today', 'آج'), p.teal,
                      () => _push(const InstPlansScreen())),
                ),
              ]),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [for (final t in tiles) _tile(p, t)],
              ),
              if (Session.isAdminOrManager) const InstTrendChart(),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _tapStat(AppPalette p, String label, String value, String sub, Color c, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: instCard(p),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 11.5))),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 10.5)),
          ]),
        ),
      );

  Widget _tile(AppPalette p, _Tile t) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: t.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: instCard(p, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: t.color.withOpacity(0.13), borderRadius: BorderRadius.circular(12)),
              child: Icon(t.icon, color: t.color, size: 26),
            ),
            const Spacer(),
            Text(t.title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 15.5)),
            const SizedBox(height: 2),
            Text(t.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 11.5)),
          ]),
        ),
      );
}

class _Tile {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _Tile(this.icon, this.title, this.subtitle, this.color, this.onTap);
}
