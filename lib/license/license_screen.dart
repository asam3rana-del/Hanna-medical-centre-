import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../db/app_database.dart';
import '../services/demo_mode.dart';
import '../services/session.dart';
import '../sync/sync_repository.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'license_core.dart';
import 'license_service.dart';

String licenseStatusText(LicenseStatus st) => switch (st) {
      LicenseStatus.missing => Loc.t('No license yet', 'ابھی لائسنس نہیں'),
      LicenseStatus.invalid => Loc.t('Key is not valid', 'کی درست نہیں'),
      LicenseStatus.wrongDevice => Loc.t('This key is for another device', 'یہ کی کسی اور ڈیوائس کی ہے'),
      LicenseStatus.revoked => Loc.t('This license was stopped', 'یہ لائسنس بند کر دیا گیا'),
      LicenseStatus.clockBack => Loc.t('Phone date / time is wrong', 'فون کی تاریخ / وقت غلط ہے'),
      LicenseStatus.active => Loc.t('Active', 'فعال'),
      LicenseStatus.expiringSoon => Loc.t('Ending soon', 'جلد ختم'),
      LicenseStatus.expired => Loc.t('Expired', 'ختم'),
    };

/// License ki maloomat + nayi key. [gate] = app isi ke peeche band hai (pehli dafa / ghalat key).
class LicenseScreen extends StatefulWidget {
  final bool gate;
  final VoidCallback? onActivated;
  const LicenseScreen({super.key, this.gate = false, this.onActivated});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _key = TextEditingController();
  String _device = '';
  LicenseStatus? _st;
  String? _msg;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await LicenseService.instance.deviceCode();
    final st = await LicenseService.instance.check();
    if (!mounted) return;
    setState(() {
      _device = d;
      _st = st;
    });
  }

  Future<void> _activate() async {
    if (_key.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    final st = await LicenseService.instance.activate(_key.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _st = LicenseService.instance.status.value ?? st;
      _msg = st.writable ? null : licenseStatusText(st);
    });
    if (st.writable) {
      _key.clear();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(Loc.t('License activated ✓', 'لائسنس فعال ہو گیا ✓'))));
      widget.onActivated?.call();
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _key.text = d!.text!.trim());
  }

  Future<void> _sendCode() async {
    final shop = Session.displayName;
    final text = '${AppInfo.appName} license\nDevice code: ${formatDeviceCode(_device)}'
        '${shop.isNotEmpty ? '\nName: $shop' : ''}\n(Trial / Annual)';
    try {
      await launchUrl(Uri.parse('https://wa.me/${AppInfo.supportWhatsAppIntl}?text=${Uri.encodeComponent(text)}'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _demo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Loc.t('Try demo shop?', 'ڈیمو دکان آزمائیں؟')),
        content: Text(Loc.t('A separate practice shop with no license. Nothing is saved to a real shop. Exit Demo from Settings.',
            'لائسنس کے بغیر الگ پریکٹس دکان۔ اصل دکان میں کچھ نہیں جاتا۔ ڈیمو سیٹنگز سے بند کریں۔')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Loc.t('Open demo', 'ڈیمو کھولیں'))),
        ],
      ),
    );
    if (ok != true) return;
    await SyncRepository.waitIdle();
    await AppDatabase.instance.close();
    await Session.clear();
    await DemoMode.setEnabled(true); // MaterialApp dobara banta hai (Settings ka demo switch jaisa)
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final info = LicenseService.instance.info;
    final st = _st;
    final good = st?.writable ?? false;
    final color = st == null ? p.textMuted : (good ? (st == LicenseStatus.expiringSoon ? p.amber : p.teal) : p.red);
    final today = DateTime.now();
    final df = DateFormat('dd MMM yyyy');
    return Scaffold(
      backgroundColor: p.bg,
      appBar: widget.gate
          ? null
          : AppBar(backgroundColor: p.navy, foregroundColor: Colors.white, title: Text(Loc.t('License', 'لائسنس'))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (widget.gate) ...[
            const SizedBox(height: 20),
            Icon(Icons.verified_user_outlined, size: 56, color: p.navy),
            const SizedBox(height: 10),
            Text(AppInfo.appName, textAlign: TextAlign.center, style: TextStyle(color: p.textDark, fontSize: 22, fontWeight: FontWeight.bold)),
            Text(Loc.t('Activate this device to start', 'شروع کرنے کے لیے یہ ڈیوائس فعال کریں'),
                textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
            const SizedBox(height: 20),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(good ? Icons.check_circle : Icons.error_outline, color: color),
                  const SizedBox(width: 8),
                  Text(st == null ? '...' : licenseStatusText(st), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
                if (info != null) ...[
                  const SizedBox(height: 10),
                  Text('${info.typeName} • ${Loc.t('Serial', 'سیریل')} ${info.serial}', style: TextStyle(color: p.textDark)),
                  Text('${Loc.t('Valid till', 'تک')} ${df.format(info.expiry)}'
                      '${info.daysLeft(today) > 0 ? '  (${Loc.t('${info.daysLeft(today)} days left', '${info.daysLeft(today)} دن باقی')})' : ''}',
                      style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
                ],
                if (st == LicenseStatus.clockBack)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(LicenseService.blockedMessage(st!), style: TextStyle(color: p.red)),
                  ),
                if (st == LicenseStatus.expired)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(LicenseService.blockedMessage(st!), style: TextStyle(color: p.textMuted, fontSize: 12.5)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Loc.t('Device code', 'ڈیوائس کوڈ'), style: TextStyle(color: p.textMuted)),
                const SizedBox(height: 4),
                SelectableText(_device.isEmpty ? '...' : formatDeviceCode(_device),
                    style: TextStyle(color: p.navy, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontFamily: 'monospace')),
                const SizedBox(height: 6),
                Text(Loc.t('Send this code to Hanna Solutions to get a Trial or Annual key for THIS device.',
                    'یہ کوڈ Hanna Solutions کو بھیجیں — اسی ڈیوائس کے لیے ٹرائل یا سالانہ کی ملے گی۔'),
                    style: TextStyle(color: p.textMuted, fontSize: 12.5)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(Loc.t('Copy', 'کاپی')),
                    onPressed: () => Clipboard.setData(ClipboardData(text: formatDeviceCode(_device))),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                    icon: const Icon(Icons.chat, size: 18),
                    label: Text(Loc.t('Send on WhatsApp', 'واٹس ایپ پر بھیجیں')),
                    onPressed: _sendCode,
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(Loc.t('Enter license key', 'لائسنس کی درج کریں'), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _key,
                  minLines: 3,
                  maxLines: 5,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'HI1-XXXXX-XXXXX-...',
                    filled: true,
                    fillColor: p.fieldFill,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(icon: const Icon(Icons.content_paste), onPressed: _paste),
                  ),
                ),
                if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: p.red))),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: p.teal, minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _activate,
                  icon: const Icon(Icons.key),
                  label: Text(_busy ? Loc.t('Checking...', 'چیک ہو رہی ہے...') : Loc.t('Activate', 'فعال کریں')),
                ),
              ]),
            ),
          ),
          if (widget.gate) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _demo,
              icon: const Icon(Icons.school_outlined),
              label: Text(Loc.t('Try demo shop (no license)', 'ڈیمو دکان آزمائیں (لائسنس کے بغیر)')),
            ),
            Text('${AppInfo.business} • ${AppInfo.supportPhone}', textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}

/// App ke shuru mein: kabhi sahi key na lagi ho (missing / invalid / wrong device) to sirf [LicenseScreen].
/// Expired / tareekh ghalat: app khulti hai, magar naya kaam band ([LicenseService.requireWritable]) + banner.
/// Demo mode: hamesha khulti hai.
class LicenseGate extends StatefulWidget {
  final Widget child;
  const LicenseGate({super.key, required this.child});

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LicenseService.instance.check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Wapas aane par dobara (raat bhar khuli app mein din badal gaya / tareekh badli).
    if (state == AppLifecycleState.resumed) LicenseService.instance.check();
  }

  @override
  Widget build(BuildContext context) {
    if (DemoMode.enabled) return widget.child;
    return ValueListenableBuilder<LicenseStatus?>(
      valueListenable: LicenseService.instance.status,
      builder: (context, st, _) {
        if (st == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (st.blocksApp) return LicenseScreen(gate: true, onActivated: () => setState(() {}));
        return widget.child;
      },
    );
  }
}

/// Home par patti: jaldi khatam / khatam / tareekh ghalat. Tap = License screen.
class LicenseBanner extends StatelessWidget {
  const LicenseBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (DemoMode.enabled) return const SizedBox.shrink();
    final p = ThemeManager.palette;
    return ValueListenableBuilder<LicenseStatus?>(
      valueListenable: LicenseService.instance.status,
      builder: (context, st, _) {
        if (st == null || st == LicenseStatus.active) return const SizedBox.shrink();
        final info = LicenseService.instance.info;
        final left = info?.daysLeft(DateTime.now()) ?? 0;
        final warn = st == LicenseStatus.expiringSoon;
        final text = switch (st) {
          LicenseStatus.expiringSoon => Loc.t('License ends in $left days — renew to keep working', 'لائسنس $left دن میں ختم — کام جاری رکھنے کے لیے رینیو کریں'),
          LicenseStatus.expired => Loc.t('License expired — view & backup only. Tap to renew.', 'لائسنس ختم — صرف دیکھنا اور بیک اپ۔ رینیو کے لیے دبائیں۔'),
          _ => LicenseService.blockedMessage(st),
        };
        return Material(
          color: (warn ? p.amber : p.red).withOpacity(0.12),
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Icon(warn ? Icons.schedule : Icons.lock_outline, color: warn ? p.amber : p.red, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600, fontSize: 13))),
                Icon(Icons.chevron_right, color: p.textMuted),
              ]),
            ),
          ),
        );
      },
    );
  }
}
