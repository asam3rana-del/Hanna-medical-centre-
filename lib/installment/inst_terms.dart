import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_ui.dart';

/// Iqrar nama ki sharait (Step 20): dukaan apni sharait likhti hai, plan ki PDF (statement / agreement) mein
/// dastakhat se pehle chhapti hain. Sirf is device par (har device par ek dafa likhein).
class InstTerms {
  InstTerms._();
  static const _key = 'inst_agreement_terms_v1';

  static const defaultUrdu = '''1. ہر قسط مقررہ تاریخ تک ادا کرنا لازم ہے، تاخیر کی صورت میں جرمانہ لگے گا۔
2. پوری ادائیگی تک سامان دکان کی ملکیت رہے گا۔
3. مسلسل دو قسطیں ادا نہ کرنے پر دکان سامان واپس لے سکتی ہے، وصول شدہ رقم واپس نہیں ہو گی۔
4. ضامن قسطوں کی ادائیگی کا برابر کا ذمہ دار ہے۔
5. سامان کی خرابی یا گم ہونے کی ذمہ داری خریدار کی ہے، وارنٹی کمپنی کے مطابق۔''';

  static const defaultEnglish = '''1. Every installment must be paid by its due date; a late fine applies after that.
2. The item remains the property of the shop until full payment.
3. If two installments in a row are missed, the shop may take the item back; money already paid is not refunded.
4. The guarantor is equally responsible for the payments.
5. The buyer is responsible for damage or loss of the item; warranty as per the company.''';

  /// Khali = sharait na chhapein (dukaan ne sab mita diya).
  static Future<String> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString(_key) ?? Loc.t(defaultEnglish, defaultUrdu);
    } catch (_) {
      return Loc.t(defaultEnglish, defaultUrdu);
    }
  }

  static Future<void> save(String text) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, text.trim());
  }

  /// PDF ke liye lines (khali lines nikal kar).
  static List<String> lines(String text) => text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}

class InstTermsScreen extends StatefulWidget {
  const InstTermsScreen({super.key});

  @override
  State<InstTermsScreen> createState() => _InstTermsScreenState();
}

class _InstTermsScreenState extends State<InstTermsScreen> {
  final _c = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    InstTerms.load().then((t) {
      if (!mounted) return;
      setState(() {
        _c.text = t;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await InstTerms.save(_c.text);
    if (!mounted) return;
    instToast(context, Loc.t('Saved. Printed on every plan PDF.', 'محفوظ ہو گیا۔ ہر پلان کی PDF میں چھپے گا۔'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Agreement terms', 'اقرار نامہ کی شرائط'),
            Loc.t('Printed on the plan PDF above signatures', 'پلان کی PDF میں دستخط سے پہلے')),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
                  TextField(
                    controller: _c,
                    minLines: 8,
                    maxLines: 20,
                    decoration: instDeco(p, Loc.t('One term per line', 'ہر شرط الگ لائن میں')),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    TextButton(
                      onPressed: () => setState(() => _c.text = InstTerms.defaultUrdu),
                      child: const Text('اردو نمونہ'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _c.text = InstTerms.defaultEnglish),
                      child: const Text('English sample'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: p.teal, minimumSize: const Size.fromHeight(48)),
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(Loc.t('Save', 'محفوظ کریں')),
                  ),
                ]),
        ),
      ]),
    );
  }
}
