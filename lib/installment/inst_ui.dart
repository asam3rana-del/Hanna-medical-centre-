import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_manager.dart';

/// Installment screens ke chhote mushtarka widgets (workers_screen jaisa flat design: navy header, safed cards).

String instPlain(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

/// Rs 125,000
String instRs(double v) {
  final neg = v < 0;
  final s = instPlain(v.abs());
  final parts = s.split('.');
  final whole = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  return 'Rs ${neg ? '-' : ''}$b${parts.length > 1 ? '.${parts[1]}' : ''}';
}

void instToast(BuildContext c, String m) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

String instErr(Object e) {
  if (e is ArgumentError) return '${e.message}';
  if (e is StateError) return e.message;
  return e.toString();
}

BoxDecoration instCard(AppPalette p, [double r = 16]) => BoxDecoration(
      color: p.cardWhite,
      borderRadius: BorderRadius.circular(r),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
    );

InputDecoration instDeco(AppPalette p, String label, {String? hint, Widget? suffix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: p.textMuted),
      hintStyle: TextStyle(color: p.textMuted),
      filled: true,
      fillColor: p.fieldFill,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.teal)),
    );

Widget instHeader(BuildContext context, AppPalette p, String title, String subtitle,
    {List<Widget> actions = const [], bool back = true, Widget? leading}) {
  return Container(
    color: p.navy,
    padding: EdgeInsets.fromLTRB(back || leading != null ? 8 : 18, MediaQuery.of(context).padding.top + 10, 8, 14),
    child: Row(children: [
      if (back)
        IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.of(context).maybePop()),
      if (leading != null) leading,
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 18.5, fontWeight: FontWeight.bold)),
          if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(color: p.headerSubtitleColor, fontSize: 11)),
        ]),
      ),
      ...actions,
    ]),
  );
}

Widget instSectionTitle(AppPalette p, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(text, style: TextStyle(color: p.textMuted, fontWeight: FontWeight.bold, fontSize: 12.5, letterSpacing: 0.3)),
    );

/// Label: value ki ek line (detail cards ke liye). Khali value => kuch nahi.
Widget instInfoLine(AppPalette p, String label, String value) {
  if (value.trim().isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120, child: Text(label, style: TextStyle(color: p.textMuted, fontSize: 13))),
      Expanded(child: SelectableText(value, style: TextStyle(color: p.textDark, fontSize: 14, fontWeight: FontWeight.w600))),
    ]),
  );
}

/// CNIC field: sirf hindse, khud dash lagata hai (35202-1234567-1).
class CnicInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 13) d = d.substring(0, 13);
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 5 || i == 12) b.write('-');
      b.write(d[i]);
    }
    final t = b.toString();
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

double instParse(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

Widget instPrimaryButton(AppPalette p, String label, VoidCallback? onPressed, {IconData? icon}) => SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.teal,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.check),
        label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );

/// Step 31: munafa sirf Reports mein — plan / naqd sale / item screens par nahi (dukaandar ki farmaish).
const kShowProfitOutsideReports = false;

/// Step 31: scan se purchase / sale abhi chhupa hai (code mojood, kahin dikhta nahi). true = wapas.
const kShowScan = false;
