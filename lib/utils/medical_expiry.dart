import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/product.dart';
import 'expiry.dart' show parseExpiry, daysUntilExpiry;

/// Hanna Pharmacy POS: batch / expiry helpers (Kotlin MedicalHelpers.kt ka port).
///
/// Expiry "yyyy-MM" mein jama hoti hai (e.g. "2027-06") kyun ke dawai par sirf mahina/saal chhapa hota
/// hai ("EXP 06/27"). Pack us mahine ke AAKHRI din tak valid samjha jata hai.
///
/// Batch ka alag stock table nahi (warna har sale/return/edit ka stock path badalna parta). Har purchase
/// line apna batchNo + expiry rakhti hai, aur [MedicalBatches.activeBatches] product ke MAUJOODA stock ko
/// purchase lines par naye-se-purane (FIFO: purani dawai pehle bikti hai) baant deta hai. Ye andaza hai.
class MedicalExpiry {
  static const nearDays = 90;

  /// "06/27", "6/27", "06/2027", "06-27", "0627", "062027", "2027-06" samajhta hai.
  /// "yyyy-MM" lautata hai, khali input par '', samajh na aaye to null.
  static String? parse(String? input) {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return '';
    int? month;
    int? year;
    final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})$').firstMatch(raw);
    final mmyy = RegExp(r'^(\d{1,2})\s*[-/.\s]\s*(\d{4}|\d{2})$').firstMatch(raw);
    final digits = RegExp(r'^(\d{2})(\d{4}|\d{2})$').firstMatch(raw);
    if (iso != null) {
      year = int.parse(iso.group(1)!);
      month = int.parse(iso.group(2)!);
    } else if (mmyy != null) {
      month = int.parse(mmyy.group(1)!);
      year = int.parse(mmyy.group(2)!);
    } else if (digits != null) {
      month = int.parse(digits.group(1)!);
      year = int.parse(digits.group(2)!);
    }
    if (month == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || year < 2000 || year > 2099) return null;
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
  }

  /// "2027-06" -> "06/27" (jaise pack par). Samajh na aaye to jaisa hai waisa.
  static String display(String? stored) {
    final s = (stored ?? '').trim();
    final n = parse(s);
    if (n == null) return s;
    if (n.isEmpty) return '';
    return '${n.substring(5, 7)}/${n.substring(2, 4)}';
  }

  /// Expiry mahine ke aakhir tak kitne din (manfi = expire ho chuki). Set nahi / ghalat = null.
  static int? daysLeft(String? stored, {DateTime? now}) {
    final n = parse(stored);
    if (n == null) {
      // Product form ki poori tareekh (yyyy-MM-dd / dd/MM/yyyy) — utils/expiry.dart wala parser.
      final full = parseExpiry(stored ?? '');
      return full == null ? null : daysUntilExpiry(full, now: now);
    }
    if (n.isEmpty) return null;
    final y = int.parse(n.substring(0, 4));
    final m = int.parse(n.substring(5, 7));
    final lastDay = DateTime(y, m + 1, 0); // agle mahine ka 0 din = is mahine ka aakhri din
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    return DateTime(lastDay.year, lastDay.month, lastDay.day).difference(today).inDays;
  }

  static bool isExpired(String? stored) => (daysLeft(stored) ?? 1 << 30) < 0;

  static String statusLabel(int days) {
    if (days < 0) return 'Expired (${-days} din pehle)';
    if (days == 0) return 'Aaj expire';
    if (days <= 30) return '$days din baqi';
    if (days <= 365) return '${days ~/ 30} mahine baqi';
    return '${days ~/ 365} saal+ baqi';
  }
}

/// Ek batch jo (andazan) abhi shelf par hai.
class ActiveBatch {
  final Product product;
  final String batchNo;
  final String expiry; // "yyyy-MM" ya ''
  final double remainingSmallest;
  final String billNo; // '' = product ki apni expiry / opening stock
  final int purchasedAt;
  final String supplierName;

  const ActiveBatch({
    required this.product,
    required this.batchNo,
    required this.expiry,
    required this.remainingSmallest,
    required this.billNo,
    required this.purchasedAt,
    required this.supplierName,
  });

  int? get daysLeft => MedicalExpiry.daysLeft(expiry);

  /// Bacha stock product ki units mein ("2 box 3 strip").
  String get stockText => product.copyWith(stock: remainingSmallest).formatStockBreakdown();

  /// Cost par qeemat (product.cost primary unit par hai).
  double get costValue {
    final f = product.smallestPerUnitOf(product.unit);
    return f > 0 ? remainingSmallest / f * product.cost : 0.0;
  }
}

class MedicalBatches {
  static const _batchSql = '''
    SELECT pi.billNo AS billNo, pi.barcode AS barcode, pi.qty AS qty, pi.unit AS unit,
           pi.conversionFactor AS conversionFactor, pi.batchNo AS batchNo, pi.expiry AS expiry,
           p.createdAt AS createdAt, COALESCE(s.name, '') AS supplierName
    FROM purchase_items pi
    INNER JOIN purchases p ON p.billNo = pi.billNo
    LEFT JOIN suppliers s ON s.id = p.supplierId
    WHERE p.status != 'returned' %WHERE%
    ORDER BY p.createdAt DESC, pi.id DESC
  ''';

  /// Ek product ka maujooda stock uski purchase lines (naye pehle) par FIFO se.
  static List<ActiveBatch> spreadStock(Product product, List<Map<String, Object?>> rowsNewestFirst) {
    var remaining = product.stock;
    final out = <ActiveBatch>[];
    if (remaining <= 0) return out;
    for (final r in rowsNewestFirst) {
      if (remaining <= 0) break;
      final qty = (r['qty'] as num?)?.toDouble() ?? 0.0;
      final factor = (r['conversionFactor'] as num?)?.toDouble() ?? 0.0;
      final unit = (r['unit'] as String?) ?? '';
      final lineSmallest = factor > 0 ? qty * factor : product.toSmallestUnits(qty, unit.isEmpty ? product.unit : unit);
      if (lineSmallest <= 0) continue;
      final take = remaining < lineSmallest ? remaining : lineSmallest;
      remaining -= take;
      out.add(ActiveBatch(
        product: product,
        batchNo: (r['batchNo'] as String?) ?? '',
        expiry: MedicalExpiry.parse(r['expiry'] as String?) ?? '',
        remainingSmallest: take,
        billNo: (r['billNo'] as String?) ?? '',
        purchasedAt: (r['createdAt'] as num?)?.toInt() ?? 0,
        supplierName: (r['supplierName'] as String?) ?? '',
      ));
    }
    // Jo stock kisi purchase line se na aaye (opening stock / adjustment): product ki apni expiry.
    if (remaining > 0.0001) {
      out.add(ActiveBatch(
        product: product,
        batchNo: '',
        expiry: product.expiry.trim(),
        remainingSmallest: remaining,
        billNo: '',
        purchasedAt: 0,
        supplierName: '',
      ));
    }
    return out;
  }

  /// Sab products ke shelf par maujood batches.
  static Future<List<ActiveBatch>> activeBatches() async {
    final Database db = await AppDatabase.instance.database;
    final products = (await db.query('products', where: 'stock > 0')).map(Product.fromMap).toList();
    final rows = await db.rawQuery(_batchSql.replaceFirst('%WHERE%', ''));
    final byBarcode = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      byBarcode.putIfAbsent((r['barcode'] as String?) ?? '', () => []).add(r);
    }
    return [for (final p in products) ...spreadStock(p, byBarcode[p.barcode] ?? const [])];
  }

  static Future<List<ActiveBatch>> batchesFor(Product product) async {
    final Database db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(_batchSql.replaceFirst('%WHERE%', 'AND pi.barcode = ?'), [product.barcode]);
    return spreadStock(product, rows);
  }

  /// Sale screen par item chunte hi: expired / 30 din mein expire hone wali dawai ki warning (warna null).
  static Future<String?> saleWarning(Product product) async {
    final dated = (await batchesFor(product)).where((b) => b.daysLeft != null).toList();
    if (dated.isEmpty) return null;
    dated.sort((a, b) => a.daysLeft!.compareTo(b.daysLeft!));
    final s = dated.first;
    final d = s.daysLeft!;
    final batch = s.batchNo.isNotEmpty ? ' (Batch ${s.batchNo})' : '';
    if (d < 0) return '⚠ ${product.name}$batch EXPIRED hai — ${MedicalExpiry.display(s.expiry)}. Check kar ke dein.';
    if (d <= 30) return '⚠ ${product.name}$batch ${MedicalExpiry.display(s.expiry)} ko expire ho rahi hai ($d din).';
    return null;
  }

  /// Same formula wali doosri dawaiyan (substitute) — stock wali pehle, phir sasti.
  static List<Product> substitutes(List<Product> all, Product product) {
    final g = product.genericName.trim().toLowerCase();
    if (g.isEmpty) return const [];
    final list = all.where((p) => p.barcode != product.barcode && p.genericName.trim().toLowerCase() == g).toList();
    list.sort((a, b) {
      final sa = a.stock > 0 ? 0 : 1, sb = b.stock > 0 ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
      return a.salePrice.compareTo(b.salePrice);
    });
    return list;
  }
}

/// "Paracetamol · GSK · Rack A3" — khali hisse chhod deta hai.
extension MedicalInfo on Product {
  String get medicalInfoLine => [
        if (controlled) '℞ Parchi',
        if (genericName.trim().isNotEmpty) genericName.trim(),
        if (company.trim().isNotEmpty) company.trim(),
        if (rackLocation.trim().isNotEmpty) 'Rack ${rackLocation.trim()}',
      ].join(' · ');
}
