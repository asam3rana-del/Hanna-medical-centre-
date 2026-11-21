import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_terms.dart';
import 'inst_ui.dart';

/// Plan ke dastakhat KycPhotoStore mein: owner 'p', id = plan id.
const planSignCustomer = 'signC';
const planSignGuarantor = 'signG';

/// Ungli / stylus se dastakhat (Step 32). Bina package: lakeeren yaad, PNG mein save.
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];
  Size size = Size.zero;

  bool get isEmpty => strokes.every((s) => s.length < 2);

  void start(Offset o) {
    strokes.add([o]);
    notifyListeners();
  }

  void add(Offset o) {
    if (strokes.isEmpty) return;
    strokes.last.add(o);
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  /// Safed pass-e-manzar par kaali lakeeren, temp folder mein PNG. Khali => null.
  Future<String?> toPngFile(String name) async {
    if (isEmpty || size.isEmpty) return null;
    const scale = 2.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.scale(scale);
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    _paintStrokes(c, strokes);
    final img = await rec.endRecording().toImage((size.width * scale).round(), (size.height * scale).round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, '${name}_${DateTime.now().millisecondsSinceEpoch}.png'));
    await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return f.path;
  }
}

void _paintStrokes(Canvas c, List<List<Offset>> strokes) {
  final paint = Paint()
    ..color = const Color(0xFF111111)
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final s in strokes) {
    if (s.length < 2) continue;
    final path = Path()..moveTo(s.first.dx, s.first.dy);
    for (final o in s.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    c.drawPath(path, paint);
  }
}

class _SigPainter extends CustomPainter {
  final SignatureController ctrl;
  _SigPainter(this.ctrl) : super(repaint: ctrl);

  @override
  void paint(Canvas canvas, Size size) => _paintStrokes(canvas, ctrl.strokes);

  @override
  bool shouldRepaint(covariant _SigPainter old) => true;
}

/// Dastakhat ka dabba: label, saaf karne ka button.
class SignaturePad extends StatelessWidget {
  final SignatureController controller;
  final String label;
  const SignaturePad({super.key, required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold))),
        TextButton.icon(
          onPressed: controller.clear,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(Loc.t('Clear', 'صاف کریں')),
        ),
      ]),
      Container(
        height: 170,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (ctx, box) {
          controller.size = Size(box.maxWidth, box.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => controller.start(d.localPosition),
            onPanUpdate: (d) => controller.add(d.localPosition),
            child: CustomPaint(painter: _SigPainter(controller), size: Size.infinite),
          );
        }),
      ),
    ]);
  }
}

/// Plan banne se pehle iqrar nama: khulasa + sharait + customer (aur zamin) ke dastakhat.
class AgreementSignResult {
  final String? customerSig;
  final String? guarantorSig;
  const AgreementSignResult(this.customerSig, this.guarantorSig);
}

class InstAgreementSignScreen extends StatefulWidget {
  final String customerName;
  final String? guarantorName;
  final List<String> summary;
  const InstAgreementSignScreen({super.key, required this.customerName, this.guarantorName, required this.summary});

  @override
  State<InstAgreementSignScreen> createState() => _InstAgreementSignScreenState();
}

class _InstAgreementSignScreenState extends State<InstAgreementSignScreen> {
  final _c = SignatureController();
  final _g = SignatureController();
  List<String> _terms = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    InstTerms.load().then((t) {
      if (mounted) setState(() => _terms = InstTerms.lines(t));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _g.dispose();
    super.dispose();
  }

  Future<void> _done(bool signed) async {
    if (_busy) return;
    if (signed && _c.isEmpty) {
      instToast(context, Loc.t('Customer signature is required.', 'کسٹمر کے دستخط ضروری ہیں۔'));
      return;
    }
    setState(() => _busy = true);
    final cs = signed ? await _c.toPngFile('sigC') : null;
    final gs = signed && widget.guarantorName != null ? await _g.toPngFile('sigG') : null;
    if (mounted) Navigator.pop(context, AgreementSignResult(cs, gs));
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Agreement', 'اقرار نامہ'), Loc.t('Read, then sign', 'پڑھیں، پھر دستخط کریں')),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: instCard(p),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final l in widget.summary)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(l, style: TextStyle(color: p.textDark))),
              ]),
            ),
            if (_terms.isNotEmpty) ...[
              instSectionTitle(p, Loc.t('TERMS', 'شرائط')),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: instCard(p),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final t in _terms)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(t, style: TextStyle(color: p.textDark, height: 1.5))),
                  const SizedBox(height: 6),
                  Text(Loc.t('I have read and accept the above terms.', 'میں نے اوپر دی گئی شرائط پڑھ کر قبول کیں۔'),
                      style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            SignaturePad(controller: _c, label: '${Loc.t('Customer signature', 'کسٹمر کے دستخط')}: ${widget.customerName}'),
            if (widget.guarantorName != null) ...[
              const SizedBox(height: 14),
              SignaturePad(controller: _g, label: '${Loc.t('Guarantor signature', 'ضامن کے دستخط')}: ${widget.guarantorName}'),
            ],
            const SizedBox(height: 20),
            instPrimaryButton(p, _busy ? Loc.t('Saving...', 'محفوظ ہو رہا ہے...') : Loc.t('Signed — create plan', 'دستخط ہو گئے — پلان بنائیں'),
                _busy ? null : () => _done(true),
                icon: Icons.draw_outlined),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => _done(false),
              child: Text(Loc.t('Create without signature (sign on paper)', 'بغیر دستخط بنائیں (کاغذ پر دستخط)')),
            ),
          ]),
        ),
      ]),
    );
  }
}
