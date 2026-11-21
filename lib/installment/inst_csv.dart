import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Report ko Excel (CSV) mein (Step 25). Pehli lines: title / tareekh / summary, phir khali line, phir table.
/// PURE — test/installment_csv_test.dart.
String csvText({
  required String title,
  String sub = '',
  List<(String, String)> summary = const [],
  required List<String> headers,
  required List<List<String>> rows,
}) {
  String cell(String v) {
    // Raqam "Rs 1,200" => 1200 taake Excel mein jama ho sake.
    final money = RegExp(r'^-?\s*Rs\.?\s*-?[\d,]+(\.\d+)?$');
    var t = v.trim();
    if (money.hasMatch(t)) {
      final neg = t.startsWith('-') || t.contains('Rs -') || t.contains('Rs-');
      t = (neg ? '-' : '') + t.replaceAll(RegExp(r'[^\d.]'), '');
    }
    // Excel formula injection se bachao (=, +, -, @ se shuru text). Minus number theek hai.
    if (RegExp(r'^[=+@]').hasMatch(t) || (t.startsWith('-') && double.tryParse(t) == null)) t = "'$t";
    if (t.contains(RegExp(r'[",\n\r]'))) t = '"${t.replaceAll('"', '""')}"';
    return t;
  }

  final b = StringBuffer();
  b.writeln(cell(title));
  if (sub.isNotEmpty) b.writeln(cell(sub));
  for (final (k, v) in summary) {
    b.writeln('${cell(k)},${cell(v)}');
  }
  b.writeln();
  b.writeln(headers.map(cell).join(','));
  for (final r in rows) {
    b.writeln(r.map(cell).join(','));
  }
  return b.toString();
}

class InstCsv {
  InstCsv._();

  /// File bana kar share sheet (WhatsApp / Drive / email). UTF-8 BOM: Excel mein Urdu theek dikhe.
  static Future<void> share({required String base, required String text}) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'reports'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final clean = base.trim().replaceAll(RegExp(r'[^\w؀-ۿ-]+'), '_');
    final f = File(p.join(dir.path, '${clean.isEmpty ? 'Report' : clean}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv'));
    await f.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(text)], flush: true);
    try {
      await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: base);
    } catch (_) {
      final r = await OpenFilex.open(f.path, type: 'text/csv');
      if (r.type != ResultType.done) rethrow;
    }
  }
}
