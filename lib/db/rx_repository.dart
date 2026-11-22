import 'package:sqflite/sqflite.dart';

import '../sync/sync_queue_helper.dart';
import '../sync/sync_worker.dart';
import 'app_database.dart';

/// Hanna Pharmacy POS: Controlled drugs / parchi (prescription) record.
///
/// Jab bill mein koi "Controlled (Rx)" dawai ho, Sale save hone se pehle patient, doctor aur parchi
/// number poocha jata hai aur yahan bill (invoice) ke saath jama hota hai. Cloud sync: record sale ke
/// doc ke andar `rx` field mein jata hai (alag collection nahi), is liye doosre device par bhi pahunchta hai.
class RxRecord {
  final String invoice;
  final String patientName;
  final String patientPhone;
  final String doctorName;
  final String prescriptionNo;
  final int createdAt;

  const RxRecord({
    required this.invoice,
    required this.patientName,
    this.patientPhone = '',
    required this.doctorName,
    this.prescriptionNo = '',
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'invoice': invoice,
        'patientName': patientName,
        'patientPhone': patientPhone,
        'doctorName': doctorName,
        'prescriptionNo': prescriptionNo,
        'createdAt': createdAt,
      };

  factory RxRecord.fromMap(Map<String, Object?> m) => RxRecord(
        invoice: (m['invoice'] as String?) ?? '',
        patientName: (m['patientName'] as String?) ?? '',
        patientPhone: (m['patientPhone'] as String?) ?? '',
        doctorName: (m['doctorName'] as String?) ?? '',
        prescriptionNo: (m['prescriptionNo'] as String?) ?? '',
        createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
      );

  /// Sale sync payload ka `rx` hissa.
  Map<String, Object?> toSync() => {
        'patientName': patientName,
        'patientPhone': patientPhone,
        'doctorName': doctorName,
        'prescriptionNo': prescriptionNo,
        'createdAt': createdAt,
      };
}

/// Register ki ek line: parchi + us bill ki controlled dawai.
class RxRegisterRow {
  final RxRecord rx;
  final int saleDate;
  final String status;
  final List<String> items; // "Tramal 50mg × 1 strip"

  const RxRegisterRow({required this.rx, required this.saleDate, required this.status, required this.items});
}

class RxRepository {
  RxRepository._();
  static final RxRepository instance = RxRepository._();

  static const createSql = '''
      CREATE TABLE IF NOT EXISTS rx_records (
        invoice TEXT PRIMARY KEY NOT NULL,
        patientName TEXT NOT NULL DEFAULT '',
        patientPhone TEXT NOT NULL DEFAULT '',
        doctorName TEXT NOT NULL DEFAULT '',
        prescriptionNo TEXT NOT NULL DEFAULT '',
        createdAt INTEGER NOT NULL DEFAULT 0
      )
  ''';

  Future<RxRecord?> get(String invoice) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('rx_records', where: 'invoice = ?', whereArgs: [invoice], limit: 1);
    return rows.isEmpty ? null : RxRecord.fromMap(rows.first);
  }

  /// Record jama karo aur bill dobara sync queue mein (taake `rx` cloud par jaye).
  Future<void> save(RxRecord r) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.insert('rx_records', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncQueueHelper.enqueueSale(txn, r.invoice);
    });
    try {
      await SyncWorker.instance.triggerNow();
    } catch (_) {}
  }

  /// Register: [fromMillis]..[toMillis] (dono shamil), naye pehle. Sirf controlled dawai ki lines dikhti hain;
  /// agar product ab controlled na raha ho to bill ki saari lines.
  Future<List<RxRegisterRow>> register({int? fromMillis, int? toMillis, String query = ''}) async {
    final db = await AppDatabase.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (fromMillis != null) {
      where.add('s.createdAt >= ?');
      args.add(fromMillis);
    }
    if (toMillis != null) {
      where.add('s.createdAt <= ?');
      args.add(toMillis);
    }
    final rows = await db.rawQuery('''
      SELECT r.*, s.createdAt AS saleDate, s.status AS saleStatus
      FROM rx_records r INNER JOIN sales s ON s.invoice = r.invoice
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY s.createdAt DESC
    ''', args);
    final q = query.trim().toLowerCase();
    final out = <RxRegisterRow>[];
    for (final m in rows) {
      final rx = RxRecord.fromMap(m);
      final items = await db.rawQuery('''
        SELECT si.product AS product, si.qty AS qty, si.unit AS unit, COALESCE(p.controlled, 0) AS controlled
        FROM sale_items si LEFT JOIN products p ON p.barcode = si.barcode
        WHERE si.invoice = ? ORDER BY si.id
      ''', [rx.invoice]);
      final controlled = items.where((i) => (i['controlled'] as num? ?? 0) == 1).toList();
      final shown = controlled.isEmpty ? items : controlled;
      final lines = [
        for (final i in shown)
          '${i['product']} × ${_qty((i['qty'] as num?)?.toDouble() ?? 0)} ${(i['unit'] as String?) ?? ''}'.trim()
      ];
      if (q.isNotEmpty) {
        final hay = '${rx.patientName} ${rx.patientPhone} ${rx.doctorName} ${rx.prescriptionNo} ${rx.invoice} ${lines.join(' ')}'
            .toLowerCase();
        if (!hay.contains(q)) continue;
      }
      out.add(RxRegisterRow(
        rx: rx,
        saleDate: (m['saleDate'] as num?)?.toInt() ?? rx.createdAt,
        status: (m['saleStatus'] as String?) ?? 'active',
        items: lines,
      ));
    }
    return out;
  }

  static String _qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

/// Sync: sale payload mein `rx` (agar record ho). Purane schema / test DB mein table na ho to chup chaap null.
Future<Map<String, Object?>?> rxSyncFor(DatabaseExecutor ex, String invoice) async {
  try {
    final rows = await ex.query('rx_records', where: 'invoice = ?', whereArgs: [invoice], limit: 1);
    return rows.isEmpty ? null : RxRecord.fromMap(rows.first).toSync();
  } catch (_) {
    return null;
  }
}

/// Sync apply: doosre device se aaya `rx` local table mein. Table na ho to kuch nahi.
Future<void> applyRxFromSale(DatabaseExecutor ex, String invoice, Object? rx) async {
  if (rx is! Map) return;
  try {
    await ex.insert(
      'rx_records',
      {
        'invoice': invoice,
        'patientName': (rx['patientName'] ?? '').toString(),
        'patientPhone': (rx['patientPhone'] ?? '').toString(),
        'doctorName': (rx['doctorName'] ?? '').toString(),
        'prescriptionNo': (rx['prescriptionNo'] ?? '').toString(),
        'createdAt': (rx['createdAt'] as num?)?.toInt() ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  } catch (_) {}
}
