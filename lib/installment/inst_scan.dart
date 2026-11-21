import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show InputImage, TextRecognitionScript, TextRecognizer;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart'
    show BarcodeCapture, BarcodeFormat, DetectionSpeed, MobileScanner, MobileScannerController;

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_cash_sale_screens.dart';
import 'inst_items_screen.dart';
import 'inst_models.dart';
import 'inst_plans_screen.dart';
import 'inst_repository.dart';
import 'inst_ui.dart';

// ================================================================== pure (test/installment_scan_test.dart)

/// Scan (camera ki tasveer ka text / barcode gun / haath se likha) se pehchan numbers nikalo:
/// IMEI / serial / engine / chassis. Har line ke andar spaces wale hindse jode jate hain ("35 678901 234567 8").
List<String> scanCandidates(String text) {
  final out = <String>{};
  for (final raw in text.split(RegExp(r'[\r\n]+'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    // Poori line ke hindse (space / dash hata kar) — IMEI aksar tukdon mein chhapta hai.
    final joined = line.replaceAll(RegExp(r'[\s\-_/.]'), '');
    for (final m in RegExp(r'\d{8,17}').allMatches(joined)) {
      out.add(m.group(0)!);
    }
    // Harf + hindse (engine / chassis / serial), kam az kam 3 hindse. Saath wale 2-3 tukde jod kar bhi
    // ("JA05E 1234567" = JA05E-1234567).
    final words = [
      for (final w in line.split(RegExp(r'[\s,:;]+')))
        if (normalizeIdValue(w.replaceAll(RegExp(r'[^A-Za-z0-9\-_/]'), '')).isNotEmpty)
          normalizeIdValue(w.replaceAll(RegExp(r'[^A-Za-z0-9\-_/]'), '')),
    ];
    for (var i = 0; i < words.length; i++) {
      for (var n = 1; n <= 3 && i + n <= words.length; n++) {
        final t = words.sublist(i, i + n).join();
        if (t.length >= 5 && t.length <= 25 && RegExp(r'\d').allMatches(t).length >= 3) out.add(t);
      }
    }
  }
  return out.toList();
}

/// [candidates] se milte pieces. Poora number barabar = pakka; 8+ hindse ka hissa = bhi theek
/// (tasveer mein aadha number aaya ho). In-stock pehle.
List<InstItem> matchScan(List<InstItem> items, List<String> candidates) {
  final cs = candidates.map(normalizeIdValue).where((c) => c.length >= 5).toSet();
  if (cs.isEmpty) return const [];
  final exact = <InstItem>[];
  final partial = <InstItem>[];
  for (final it in items) {
    final ids = it.idValues.values.map(normalizeIdValue).where((v) => v.length >= 5).toList();
    if (ids.isEmpty) continue;
    if (ids.any(cs.contains)) {
      exact.add(it);
    } else if (ids.any((v) => cs.any((c) => (c.length >= 8 && v.contains(c)) || (v.length >= 8 && c.contains(v))))) {
      partial.add(it);
    }
  }
  int byStock(InstItem a, InstItem b) => (a.inStock ? 0 : 1) - (b.inStock ? 0 : 1);
  exact.sort(byStock);
  partial.sort(byStock);
  return exact.isNotEmpty ? exact : partial;
}

// ================================================================== screen

/// Scanner se sale (Step 19): IMEI / serial scan karo -> piece milta hai -> Naqd sale ya Qist par.
/// Mobile: camera se tasveer (ML Kit text, phone par hi, internet nahi). PC / mobile: USB / Bluetooth barcode
/// scanner (keyboard ki tarah likhta hai) ya haath se number.
class InstScanSaleScreen extends StatefulWidget {
  const InstScanSaleScreen({super.key});

  @override
  State<InstScanSaleScreen> createState() => _InstScanSaleScreenState();
}

class _InstScanSaleScreenState extends State<InstScanSaleScreen> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  List<InstItem> _items = const [];
  List<InstCategory> _cats = const [];
  List<InstItem>? _found;
  String _info = '';
  bool _busy = false;

  bool get _hasCamera => !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await InstRepository.instance.items();
    final cats = await InstRepository.instance.categories();
    if (mounted) {
      setState(() {
        _items = items;
        _cats = cats;
      });
    }
  }

  void _search(String text, {String source = ''}) {
    final cands = scanCandidates(text);
    final found = matchScan(_items, cands);
    setState(() {
      _found = found;
      _info = cands.isEmpty
          ? Loc.t('No number found. Try again closer, in good light.', 'کوئی نمبر نہیں ملا۔ قریب سے، روشنی میں دوبارہ کوشش کریں۔')
          : found.isEmpty
              ? '${Loc.t('Not in stock records', 'اسٹاک ریکارڈ میں نہیں')}: ${cands.take(3).join(', ')}'
              : source;
    });
    // Barcode gun agla scan foran kar sake.
    _q.clear();
    _focus.requestFocus();
  }

  /// Live barcode (dhariyan / QR). Dabbe par kai barcode hote hain (IMEI 1, IMEI 2, S/N, EAN): jo stock se mile
  /// wahi lete hain, baqi par scan chalta rehta hai.
  Future<void> _live() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => InstBarcodeScanPage(accept: (v) => matchScan(_items, scanCandidates(v)).isNotEmpty)));
    if (code == null || !mounted) return;
    _search(code, source: Loc.t('Barcode scanned', 'بارکوڈ اسکین ہوا'));
  }

  Future<void> _camera() async {
    if (_busy) return;
    setState(() => _busy = true);
    TextRecognizer? rec;
    try {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2200);
      if (shot == null) return;
      rec = TextRecognizer(script: TextRecognitionScript.latin);
      final r = await rec.processImage(InputImage.fromFilePath(shot.path));
      try {
        await File(shot.path).delete();
      } catch (_) {}
      if (!mounted) return;
      _search(r.text, source: Loc.t('Read from photo', 'تصویر سے پڑھا'));
    } catch (e) {
      if (mounted) instToast(context, '${Loc.t('Camera / scan failed', 'کیمرہ / اسکین ناکام')}: $e');
    } finally {
      await rec?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _loadItems();
    if (mounted) setState(() => _found = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final found = _found;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Scan & Sell', 'اسکین سے سیل'), Loc.t('IMEI / serial / engine no.', 'IMEI / سیریل / انجن نمبر')),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
            if (_hasCamera)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: p.teal, minimumSize: const Size.fromHeight(64)),
                onPressed: _busy ? null : _live,
                icon: const Icon(Icons.qr_code_scanner, size: 28),
                label: Text(Loc.t('Scan barcode', 'بارکوڈ اسکین کریں'), style: const TextStyle(fontSize: 17)),
              ),
            if (_hasCamera)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _camera,
                  icon: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                      : const Icon(Icons.document_scanner_outlined),
                  label: Text(Loc.t('No barcode? Photo of the number', 'بارکوڈ نہیں؟ نمبر کی تصویر')),
                ),
              ),
            if (_hasCamera)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 14),
                child: Text(
                    Loc.t('Box sticker barcode, or the printed IMEI / engine no. (photo), or *#06# screen.',
                        'ڈبے کے اسٹیکر کا بارکوڈ، یا چھپا ہوا IMEI / انجن نمبر (تصویر)، یا *#06# والی اسکرین۔'),
                    style: TextStyle(color: p.textMuted, fontSize: 12.5)),
              ),
            TextField(
              controller: _q,
              focusNode: _focus,
              autofocus: !_hasCamera,
              textInputAction: TextInputAction.search,
              decoration: instDeco(p, Loc.t('Barcode scanner / type number', 'بارکوڈ اسکینر / نمبر لکھیں'),
                  hint: Loc.t('Scan with a USB / Bluetooth scanner or type', 'USB / بلوٹوتھ اسکینر سے اسکین یا لکھیں'),
                  suffix: IconButton(icon: const Icon(Icons.search), onPressed: () => _search(_q.text))),
              onSubmitted: (t) => _search(t),
            ),
            const SizedBox(height: 14),
            if (_info.isNotEmpty) Text(_info, style: TextStyle(color: found != null && found.isEmpty ? p.red : p.textMuted)),
            if (found != null)
              for (final it in found) _result(p, it),
          ]),
        ),
      ]),
    );
  }

  Widget _result(AppPalette p, InstItem it) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: instCard(p),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(it.title.isEmpty ? it.model : it.title,
                style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Text(instStatusLabel(it.status),
              style: TextStyle(color: it.inStock ? p.teal : p.red, fontWeight: FontWeight.bold, fontSize: 12.5)),
        ]),
        if (it.primaryId.isNotEmpty) Text(it.primaryId, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
        if (it.color.isNotEmpty) Text(it.color, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
        if (it.cashPrice > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${Loc.t('Cash price', 'نقد قیمت')}: ${instRs(it.cashPrice)}',
                style: TextStyle(color: p.textDark, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 10),
        if (it.inStock && it.id != null)
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: p.teal, minimumSize: const Size.fromHeight(46)),
                onPressed: () => _go(NewInstallmentScreen(itemId: it.id)),
                icon: const Icon(Icons.add_card),
                label: Text(Loc.t('On installment', 'قسط پر')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: p.navyLight, minimumSize: const Size.fromHeight(46)),
                onPressed: () => _go(InstNewCashSaleScreen(itemId: it.id)),
                icon: const Icon(Icons.point_of_sale),
                label: Text(Loc.t('Cash sale', 'نقد سیل')),
              ),
            ),
          ])
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: () => _go(InstItemFormScreen(categories: _cats, existing: it)),
            icon: const Icon(Icons.info_outline),
            label: Text(Loc.t('Already sold — view details', 'پہلے بک چکا — تفصیل دیکھیں')),
          ),
      ]),
    );
  }
}


/// Live camera barcode scanner (Android / iOS). [accept] = ye code stock mein hai? Haan => wapas; nahi => neeche
/// "nahi mila" likh kar scan jari (dabbe ka doosra barcode aazmayein).
class InstBarcodeScanPage extends StatefulWidget {
  final bool Function(String code) accept;
  const InstBarcodeScanPage({super.key, required this.accept});

  @override
  State<InstBarcodeScanPage> createState() => _InstBarcodeScanPageState();
}

class _InstBarcodeScanPageState extends State<InstBarcodeScanPage> {
  final _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.itf,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );
  final _tried = <String>[];
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final v = (b.rawValue ?? '').trim();
      if (v.isEmpty) continue;
      if (widget.accept(v)) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
      if (!_tried.contains(v)) setState(() => _tried.insert(0, v));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(Loc.t('Scan barcode', 'بارکوڈ اسکین کریں')),
        actions: [
          IconButton(
            tooltip: Loc.t('Light', 'روشنی'),
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              try {
                await _ctrl.toggleTorch();
                if (mounted) setState(() => _torch = !_torch);
              } catch (_) {}
            },
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _ctrl, onDetect: _onDetect),
        Center(
          child: Container(
            width: 300,
            height: 150,
            decoration: BoxDecoration(border: Border.all(color: Colors.greenAccent, width: 3), borderRadius: BorderRadius.circular(12)),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                Loc.t('Hold the IMEI barcode inside the box', 'IMEI والا بارکوڈ خانے کے اندر رکھیں'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              if (_tried.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${Loc.t('Not in stock', 'اسٹاک میں نہیں')}: ${_tried.take(3).join(', ')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 12.5),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
