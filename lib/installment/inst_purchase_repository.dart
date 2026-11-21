import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Sqflite;

import '../db/app_database.dart';
import '../license/license_service.dart';
import '../models/misc_entities.dart' show CashTransaction;
import '../services/session.dart';
import '../sync/sync_queue_helper.dart';
import 'inst_models.dart';
import 'inst_repository.dart';
import 'inst_sync.dart';

/// Hanna Installment — khareed (purchase) ka record.
///
/// * Supplier: jis se maal liya. Baqi (hum ne dena hai) = opening + saare bill − saari adaigi.
/// * Khareed ka bill: ek supplier, ek tareekh, kai pieces. Har piece `inst_items` mein (stock) `purchaseId` ke saath
///   banta hai, is liye stock / qist plan / rate badalna sab pehle jaisa. Bill ka `total` = pieces ki khareed qeemat
///   (bill banate waqt); baad mein piece ka rate badle to bill nahi badalta (jo diya tha wahi).
/// * Adaigi: har adaigi ke saath `cash_transactions` OUT row (reference `inst-supp:<id>`) — aaj ka cash poora rahe;
///   POS ka sync woh row doosre devices par le jata hai.
/// Sirf Admin / Manager (khareed qeemat cashier ko nahi dikhti).
class InstPurchaseRepository {
  InstPurchaseRepository._();
  static final InstPurchaseRepository instance = InstPurchaseRepository._();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Stock / home screens bhi sun-te hain.
  void _changed() => InstRepository.instance.changes.value++;

  /// Wapasi ke jor (v43 table; app hamesha migrate hoti hai is liye mojood).
  static const _returnedBySupplier = '(SELECT COALESCE(SUM(amount), 0) FROM inst_purchase_returns w WHERE w.supplierId = s.id)';
  static const _returnedByBill = '(SELECT COALESCE(SUM(amount), 0) FROM inst_purchase_returns w WHERE w.purchaseId = p.id)';

  void _requireManager() {
    if (!Session.isAdminOrManager) throw ArgumentError('Khareed sirf Admin / Manager darj kar sakta hai.');
  }

  // ================================================================ suppliers

  Future<List<InstSupplierRow>> suppliers() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT s.*,
        (SELECT COALESCE(SUM(total), 0) FROM inst_purchases p WHERE p.supplierId = s.id) AS purchased,
        (SELECT COALESCE(SUM(amount), 0) FROM inst_supplier_payments y WHERE y.supplierId = s.id) AS paid,
        $_returnedBySupplier AS returned
      FROM inst_suppliers s
      ORDER BY s.name COLLATE NOCASE ASC
    ''');
    return [
      for (final r in rows)
        InstSupplierRow(
          supplier: InstSupplier.fromMap(r),
          purchased: ((r['purchased'] as num?) ?? 0).toDouble(),
          paid: ((r['paid'] as num?) ?? 0).toDouble(),
          returned: ((r['returned'] as num?) ?? 0).toDouble(),
        )
    ];
  }

  Future<InstSupplierRow?> supplierRow(int id) async {
    for (final r in await suppliers()) {
      if (r.supplier.id == id) return r;
    }
    return null;
  }

  Future<int> saveSupplier(InstSupplier s) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    _requireManager();
    final name = s.name.trim();
    if (name.isEmpty) throw ArgumentError('Supplier ka naam likhein.');
    if (!phoneValid(s.phone)) throw ArgumentError('Phone number theek nahi (03xx xxxxxxx).');
    if (!s.openingBalance.isFinite) throw ArgumentError('Purana baqi theek nahi.');
    final db = await AppDatabase.instance.database;
    final clash = await db.rawQuery(
        'SELECT id FROM inst_suppliers WHERE LOWER(TRIM(name)) = ? AND id != ? LIMIT 1', [name.toLowerCase(), s.id ?? -1]);
    if (clash.isNotEmpty) throw ArgumentError('"$name" naam ka supplier pehle se hai.');
    final now = _now();
    final row = <String, Object?>{
      'name': name,
      'phone': s.phone.trim(),
      'address': s.address.trim(),
      'note': s.note.trim(),
      'openingBalance': s.openingBalance,
      'updatedAt': now,
    };
    final id = await db.transaction((txn) async {
      int id;
      if (s.id == null) {
        id = await txn.insert('inst_suppliers', {...row, 'createdAt': now});
      } else {
        await txn.update('inst_suppliers', row, where: 'id = ?', whereArgs: [s.id]);
        id = s.id!;
        // Pieces par supplier ka naam bhi (stock list / search mein wahi dikhe).
        final pids = await txn.query('inst_purchases', columns: ['id'], where: 'supplierId = ?', whereArgs: [id]);
        for (final p in pids) {
          final items = await txn.query('inst_items',
              columns: ['id'], where: 'purchaseId = ? AND supplier != ?', whereArgs: [p['id'], name]);
          for (final it in items) {
            await txn.update('inst_items', {'supplier': name, 'updatedAt': now}, where: 'id = ?', whereArgs: [it['id']]);
            await InstSync.enqueueItem(txn, (it['id'] as num).toInt());
          }
        }
      }
      await InstSync.enqueueSupplier(txn, id);
      return id;
    });
    _changed();
    return id;
  }

  /// Sirf woh supplier jis ka koi bill / adaigi nahi.
  Future<void> deleteSupplier(int id) async {
    _requireManager();
    final db = await AppDatabase.instance.database;
    final n = (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_purchases WHERE supplierId = ?', [id])) ?? 0) +
        (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_supplier_payments WHERE supplierId = ?', [id])) ?? 0) +
        (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_purchase_returns WHERE supplierId = ?', [id])) ?? 0);
    if (n > 0) throw ArgumentError('Is supplier ke bill / adaigi darj hain — delete nahi ho sakta.');
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instSupplierType, 'inst_suppliers', 'id', id);
      await txn.delete('inst_suppliers', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  // ================================================================ purchases

  /// Naya khareed ka bill + us ke pieces (stock mein) + abhi di gayi raqam (0 = sab udhaar). Wapas: bill id.
  /// [items]: form se bane pieces (id null); supplier / tareekh / status yahan lagte hain.
  Future<int> createPurchase({
    required int supplierId,
    required List<InstItem> items,
    String billNo = '',
    int? purchaseDate,
    String note = '',
    double paidNow = 0,
    String method = 'cash',
  }) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    _requireManager();
    if (items.isEmpty) throw ArgumentError('Kam az kam ek piece shamil karein.');
    if (!paidNow.isFinite || paidNow < 0) throw ArgumentError('Di gayi raqam theek nahi.');
    if (method != 'cash' && method != 'bank') throw ArgumentError('Cash ya Bank chunein.');
    final db = await AppDatabase.instance.database;
    final sup = await db.query('inst_suppliers', where: 'id = ?', whereArgs: [supplierId], limit: 1);
    if (sup.isEmpty) throw ArgumentError('Supplier chunein.');
    final supName = (sup.first['name'] as String?) ?? '';
    await _checkItems(items);
    final total = items.fold<double>(0, (a, i) => a + i.costPrice);
    if (paidNow > total + 0.5) throw ArgumentError('Di gayi raqam bill (${total.round()}) se zyada hai.');
    final now = _now();
    final day = _dayStart(purchaseDate ?? now);
    final id = await db.transaction((txn) async {
      final pid = await txn.insert('inst_purchases', {
        'billNo': billNo.trim(),
        'supplierId': supplierId,
        'purchaseDate': day,
        'total': total,
        'note': note.trim(),
        'createdBy': Session.username ?? '',
        'createdAt': now,
        'updatedAt': now,
      });
      if (billNo.trim().isEmpty) {
        await txn.update('inst_purchases', {'billNo': 'K-$pid'}, where: 'id = ?', whereArgs: [pid]);
      }
      await InstSync.enqueuePurchase(txn, pid);
      await _insertItems(txn, items, purchaseId: pid, supplierName: supName, day: day, now: now);
      if (paidNow > 0) {
        await _insertPayment(txn,
            supplierId: supplierId, supplierName: supName, purchaseId: pid, amount: paidNow, method: method, note: '', paidAt: now);
      }
      return pid;
    });
    _changed();
    return id;
  }

  Future<void> _checkItems(List<InstItem> items) async {
    final db = await AppDatabase.instance.database;
    final catIds = {for (final r in await db.query('inst_categories', columns: ['id'])) (r['id'] as num).toInt()};
    final existing = await InstRepository.instance.items();
    final checked = <InstItem>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final n = i + 1;
      if (it.model.trim().isEmpty) throw ArgumentError('Piece $n: model / naam likhein.');
      if (!catIds.contains(it.categoryId)) throw ArgumentError('Piece $n: category chunein.');
      if (!it.costPrice.isFinite || !it.cashPrice.isFinite || it.costPrice < 0 || it.cashPrice < 0) {
        throw ArgumentError('Piece $n: qeemat theek nahi.');
      }
      final dup = findDuplicateId(it, existing) ?? findDuplicateId(it, checked);
      if (dup != null) throw ArgumentError('Piece $n: $dup pehle se kisi aur piece par darj hai.');
      checked.add(it);
    }
  }

  Future<void> _insertItems(DatabaseExecutor txn, List<InstItem> items,
      {required int purchaseId, required String supplierName, required int day, required int now}) async {
    for (final it in items) {
      final clean = it.copyWith(
        brand: it.brand.trim(),
        model: it.model.trim(),
        color: it.color.trim(),
        supplier: supplierName,
        note: it.note.trim(),
        status: itemInStock,
        purchaseDate: day,
        idValues: {
          for (final e in it.idValues.entries)
            if (e.value.trim().isNotEmpty) e.key: e.value.trim()
        },
        updatedAt: now,
      );
      final iid = await txn.insert('inst_items', clean.toMap()..remove('id')..['createdAt'] = now..['purchaseId'] = purchaseId);
      await InstSync.enqueueItem(txn, iid);
    }
  }

  /// Purane bill mein reh jane wale pieces (bill ki raqam barh jati hai).
  Future<void> addItems(InstPurchase p, List<InstItem> items) async {
    await LicenseService.instance.requireWritable();
    _requireManager();
    if (items.isEmpty) throw ArgumentError('Kam az kam ek piece shamil karein.');
    await _checkItems(items);
    final db = await AppDatabase.instance.database;
    final now = _now();
    final extra = items.fold<double>(0, (a, i) => a + i.costPrice);
    await db.transaction((txn) async {
      final rows = await txn.query('inst_purchases', where: 'id = ?', whereArgs: [p.id], limit: 1);
      if (rows.isEmpty) throw ArgumentError('Bill nahi mila.');
      final total = ((rows.first['total'] as num?) ?? 0).toDouble() + extra;
      await txn.update('inst_purchases', {'total': total, 'updatedAt': now}, where: 'id = ?', whereArgs: [p.id]);
      await InstSync.enqueuePurchase(txn, p.id);
      await _insertItems(txn, items, purchaseId: p.id, supplierName: p.supplierName, day: p.purchaseDate > 0 ? p.purchaseDate : _dayStart(now), now: now);
    });
    _changed();
  }

  // ================================================================ supplier ko wapsi (v43)

  /// Bill ke stock wale pieces supplier ko wapas: piece `returned`, supplier ka baqi utna kam ([amounts] na ho to khareed qeemat).
  Future<int> returnPieces(InstPurchase p, List<InstItem> pieces, {Map<int, double> amounts = const {}, String note = ''}) async {
    await LicenseService.instance.requireWritable();
    _requireManager();
    if (pieces.isEmpty) throw ArgumentError('Wapas karne wala piece chunein.');
    final db = await AppDatabase.instance.database;
    final now = _now();
    var n = 0;
    await db.transaction((txn) async {
      for (final it in pieces) {
        final rows = await txn.query('inst_items', where: 'id = ? AND purchaseId = ?', whereArgs: [it.id, p.id], limit: 1);
        if (rows.isEmpty) throw ArgumentError('${it.title}: is bill ka piece nahi.');
        final cur = InstItem.fromMap(rows.first);
        if (!cur.inStock) throw ArgumentError('${cur.title.isEmpty ? cur.model : cur.title}: stock mein nahi — wapas nahi ho sakta.');
        final amt = amounts[cur.id] ?? cur.costPrice;
        if (!amt.isFinite || amt < 0) throw ArgumentError('Wapasi ki raqam theek nahi.');
        final rid = await txn.insert('inst_purchase_returns', {
          'supplierId': p.supplierId,
          'purchaseId': p.id,
          'itemId': cur.id,
          'amount': amt,
          'note': note.trim(),
          'returnedBy': Session.username ?? '',
          'returnedAt': now,
          'createdAt': now,
          'updatedAt': now,
        });
        await txn.update('inst_items', {'status': itemReturned, 'updatedAt': now}, where: 'id = ?', whereArgs: [cur.id]);
        await InstSync.enqueueItem(txn, cur.id!);
        await InstSync.enqueuePurchaseReturn(txn, rid);
        n++;
      }
    });
    _changed();
    return n;
  }

  /// Ghalat wapsi khatam: piece dobara stock mein, supplier ka baqi wapas.
  Future<void> cancelReturn(PurchaseReturn r) async {
    _requireManager();
    final db = await AppDatabase.instance.database;
    final now = _now();
    await db.transaction((txn) async {
      final n = await txn.update('inst_items', {'status': itemInStock, 'updatedAt': now},
          where: 'id = ? AND status = ?', whereArgs: [r.itemId, itemReturned]);
      if (n > 0) await InstSync.enqueueItem(txn, r.itemId);
      await InstSync.enqueueDeleteRow(txn, instPurchaseReturnType, 'inst_purchase_returns', 'id', r.id);
      await txn.delete('inst_purchase_returns', where: 'id = ?', whereArgs: [r.id]);
    });
    _changed();
  }

  Future<List<PurchaseReturn>> returns({int? supplierId, int? purchaseId}) async {
    final db = await AppDatabase.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (supplierId != null) {
      where.add('r.supplierId = ?');
      args.add(supplierId);
    }
    if (purchaseId != null) {
      where.add('r.purchaseId = ?');
      args.add(purchaseId);
    }
    final rows = await db.rawQuery('''
      SELECT r.*, i.brand AS brand, i.model AS model, i.idValues AS idValues
      FROM inst_purchase_returns r LEFT JOIN inst_items i ON i.id = r.itemId
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY r.returnedAt DESC, r.id DESC
    ''', args);
    return rows.map(PurchaseReturn.fromMap).toList();
  }

  /// Bill ka number / tareekh / note (pieces wahi). Tareekh badle to pieces ki khareed tareekh bhi.
  Future<void> updatePurchase(InstPurchase p, {required String billNo, required int purchaseDate, required String note}) async {
    await LicenseService.instance.requireWritable();
    _requireManager();
    final db = await AppDatabase.instance.database;
    final now = _now();
    final day = _dayStart(purchaseDate);
    await db.transaction((txn) async {
      await txn.update('inst_purchases', {'billNo': billNo.trim().isEmpty ? 'K-${p.id}' : billNo.trim(), 'purchaseDate': day, 'note': note.trim(), 'updatedAt': now},
          where: 'id = ?', whereArgs: [p.id]);
      await InstSync.enqueuePurchase(txn, p.id);
      if (day != p.purchaseDate) {
        for (final r in await txn.query('inst_items', columns: ['id'], where: 'purchaseId = ?', whereArgs: [p.id])) {
          await txn.update('inst_items', {'purchaseDate': day, 'updatedAt': now}, where: 'id = ?', whereArgs: [r['id']]);
          await InstSync.enqueueItem(txn, (r['id'] as num).toInt());
        }
      }
    });
    _changed();
  }

  /// Ghalat bill wapas: tab hi jab us ke SAARE pieces abhi stock mein hon. Pieces, bill ki adaigi (aur cash rows) bhi hat'ti hain.
  Future<void> deletePurchase(InstPurchase p) async {
    _requireManager();
    final db = await AppDatabase.instance.database;
    final items = await purchaseItems(p.id);
    if (items.any((i) => !i.inStock)) {
      throw ArgumentError('Is bill ka koi piece bik chuka / stock mein nahi — bill delete nahi ho sakta.');
    }
    await db.transaction((txn) async {
      for (final it in items) {
        await InstSync.enqueueDeleteRow(txn, instItemType, 'inst_items', 'id', it.id!);
        await txn.delete('inst_price_changes', where: 'itemId = ?', whereArgs: [it.id]);
        await txn.delete('inst_items', where: 'id = ?', whereArgs: [it.id]);
      }
      for (final pay in await txn.query('inst_supplier_payments', where: 'purchaseId = ?', whereArgs: [p.id])) {
        final payId = (pay['id'] as num).toInt();
        await InstSync.enqueueDeleteRow(txn, instSupplierPaymentType, 'inst_supplier_payments', 'id', payId);
        await txn.delete('inst_supplier_payments', where: 'id = ?', whereArgs: [payId]);
        await _deleteCash(txn, payId, (pay['cashTxId'] as num?)?.toInt());
      }
      for (final r in await txn.query('inst_purchase_returns', columns: ['id'], where: 'purchaseId = ?', whereArgs: [p.id])) {
        final rid = (r['id'] as num).toInt();
        await InstSync.enqueueDeleteRow(txn, instPurchaseReturnType, 'inst_purchase_returns', 'id', rid);
        await txn.delete('inst_purchase_returns', where: 'id = ?', whereArgs: [rid]);
      }
      await InstSync.enqueueDeleteRow(txn, instPurchaseType, 'inst_purchases', 'id', p.id);
      await txn.delete('inst_purchases', where: 'id = ?', whereArgs: [p.id]);
    });
    _changed();
  }

  /// Bill list (naye pehle). [supplierId] / tareekh [from]..[to) ka filter (null = sab).
  Future<List<InstPurchase>> purchases({int? supplierId, int? from, int? to}) async {
    final db = await AppDatabase.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (supplierId != null) {
      where.add('p.supplierId = ?');
      args.add(supplierId);
    }
    if (from != null) {
      where.add('p.purchaseDate >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('p.purchaseDate < ?');
      args.add(to);
    }
    final rows = await db.rawQuery('''
      SELECT p.*, s.name AS supplierName,
        (SELECT COALESCE(SUM(amount), 0) FROM inst_supplier_payments y WHERE y.purchaseId = p.id) AS paid,
        (SELECT COUNT(*) FROM inst_items i WHERE i.purchaseId = p.id) AS itemCount,
        $_returnedByBill AS returned
      FROM inst_purchases p
      LEFT JOIN inst_suppliers s ON s.id = p.supplierId
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY p.purchaseDate DESC, p.id DESC
    ''', args);
    return rows.map(InstPurchase.fromMap).toList();
  }

  Future<InstPurchase?> purchase(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.*, s.name AS supplierName,
        (SELECT COALESCE(SUM(amount), 0) FROM inst_supplier_payments y WHERE y.purchaseId = p.id) AS paid,
        (SELECT COUNT(*) FROM inst_items i WHERE i.purchaseId = p.id) AS itemCount,
        $_returnedByBill AS returned
      FROM inst_purchases p LEFT JOIN inst_suppliers s ON s.id = p.supplierId
      WHERE p.id = ? LIMIT 1
    ''', [id]);
    return rows.isEmpty ? null : InstPurchase.fromMap(rows.first);
  }

  Future<List<InstItem>> purchaseItems(int purchaseId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_items', where: 'purchaseId = ?', whereArgs: [purchaseId], orderBy: 'id ASC');
    return rows.map(InstItem.fromMap).toList();
  }

  // ================================================================ payments

  /// Supplier ko adaigi. [purchaseId] = kis bill ki (null = aam / purana baqi). Wapas: payment id.
  Future<int> pay({
    required int supplierId,
    int? purchaseId,
    required double amount,
    String method = 'cash',
    String note = '',
    int? paidAt,
  }) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    _requireManager();
    if (!amount.isFinite || amount <= 0) throw ArgumentError('Raqam likhein.');
    if (method != 'cash' && method != 'bank') throw ArgumentError('Cash ya Bank chunein.');
    final db = await AppDatabase.instance.database;
    final sup = await db.query('inst_suppliers', where: 'id = ?', whereArgs: [supplierId], limit: 1);
    if (sup.isEmpty) throw ArgumentError('Supplier nahi mila.');
    String bill = '';
    if (purchaseId != null) {
      final p = await purchase(purchaseId);
      if (p == null || p.supplierId != supplierId) throw ArgumentError('Bill nahi mila.');
      if (amount > p.due + 0.5) throw ArgumentError('Is bill ka baqi sirf ${p.due.round()} hai.');
      bill = p.billNo;
    }
    final id = await db.transaction((txn) => _insertPayment(txn,
        supplierId: supplierId,
        supplierName: (sup.first['name'] as String?) ?? '',
        purchaseId: purchaseId,
        bill: bill,
        amount: amount,
        method: method,
        note: note,
        paidAt: paidAt ?? _now()));
    _changed();
    return id;
  }

  Future<int> _insertPayment(
    DatabaseExecutor txn, {
    required int supplierId,
    required String supplierName,
    int? purchaseId,
    String bill = '',
    required double amount,
    required String method,
    required String note,
    required int paidAt,
  }) async {
    final now = _now();
    if (purchaseId != null && bill.isEmpty) {
      final r = await txn.query('inst_purchases', columns: ['billNo'], where: 'id = ?', whereArgs: [purchaseId], limit: 1);
      if (r.isNotEmpty) bill = (r.first['billNo'] as String?) ?? '';
    }
    final payId = await txn.insert('inst_supplier_payments', {
      'supplierId': supplierId,
      'purchaseId': purchaseId,
      'amount': amount,
      'method': method,
      'note': note.trim(),
      'paidBy': Session.username ?? '',
      'paidAt': paidAt,
      'createdAt': now,
      'updatedAt': now,
    });
    final cash = CashTransaction(
      type: 'OUT',
      method: method,
      amount: amount,
      reason: 'Supplier: $supplierName${bill.isEmpty ? '' : ' ($bill)'}',
      reference: 'inst-supp:$payId',
      createdAt: paidAt,
      updatedAt: now,
    );
    final cashId = await txn.insert('cash_transactions', cash.toMap()..remove('id'));
    await SyncQueueHelper.enqueueCashTransaction(txn, cashId);
    await txn.update('inst_supplier_payments', {'cashTxId': cashId}, where: 'id = ?', whereArgs: [payId]);
    await InstSync.enqueueSupplierPayment(txn, payId);
    return payId;
  }

  /// Ghalat adaigi wapas (saath wali cash row bhi).
  Future<void> deletePayment(InstSupplierPayment p) async {
    _requireManager();
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instSupplierPaymentType, 'inst_supplier_payments', 'id', p.id);
      await txn.delete('inst_supplier_payments', where: 'id = ?', whereArgs: [p.id]);
      await _deleteCash(txn, p.id, p.cashTxId);
    });
    _changed();
  }

  /// Adaigi ki cash row hatao: is device par bani ho to reference se, doosre device se aayi ho to cashTxId se.
  Future<void> _deleteCash(DatabaseExecutor txn, int payId, int? cashTxId) async {
    await SyncQueueHelper.deleteCashTransactionsByReference(txn, 'inst-supp:$payId');
    if (cashTxId == null) return;
    final rows = await txn.query('cash_transactions', where: 'id = ?', whereArgs: [cashTxId], limit: 1);
    if (rows.isEmpty) return;
    final row = Map<String, Object?>.from(rows.first);
    if (!(row['reference'] as String? ?? '').startsWith('inst-supp:')) return; // kisi aur ki row nahi chhedte
    await txn.delete('cash_transactions', where: 'id = ?', whereArgs: [cashTxId]);
    await SyncQueueHelper.enqueueDelete(txn, 'cash_transaction', SyncQueueHelper.cashTransactionEntityId(row));
  }

  Future<List<InstSupplierPayment>> payments({int? supplierId, int? purchaseId}) async {
    final db = await AppDatabase.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (supplierId != null) {
      where.add('supplierId = ?');
      args.add(supplierId);
    }
    if (purchaseId != null) {
      where.add('purchaseId = ?');
      args.add(purchaseId);
    }
    final rows = await db.query('inst_supplier_payments',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args, orderBy: 'paidAt DESC, id DESC');
    return rows.map(InstSupplierPayment.fromMap).toList();
  }

  // ================================================================ ledger / report

  /// Supplier ka khata: purana baqi, bill (+), adaigi (−), har line ke baad baqi. Purane pehle.
  Future<List<SupplierLedgerLine>> ledger(int supplierId) async {
    final db = await AppDatabase.instance.database;
    final s = await db.query('inst_suppliers', where: 'id = ?', whereArgs: [supplierId], limit: 1);
    if (s.isEmpty) return const [];
    final sup = InstSupplier.fromMap(s.first);
    final bills = await purchases(supplierId: supplierId);
    final pays = await payments(supplierId: supplierId);
    final rets = await returns(supplierId: supplierId);
    final billNo = {for (final b in bills) b.id: b.billNo};
    return buildSupplierLedger(sup, bills, pays, billNo, returns: rets);
  }

  /// Muddat [from]..[to) ki khareed: bill kitne, kul raqam, us muddat ki adaigi; aur aaj tak kul baqi (sab suppliers).
  Future<PurchaseSummary> summary({required int from, required int to}) async {
    final db = await AppDatabase.instance.database;
    if ((await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_purchases'")).isEmpty) {
      return const PurchaseSummary();
    }
    final b = (await db.rawQuery(
            'SELECT COUNT(*) AS n, COALESCE(SUM(total), 0) AS t FROM inst_purchases WHERE purchaseDate >= ? AND purchaseDate < ?',
            [from, to]))
        .first;
    final pieces = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*) FROM inst_items i JOIN inst_purchases p ON p.id = i.purchaseId
          WHERE p.purchaseDate >= ? AND p.purchaseDate < ?''', [from, to])) ??
        0;
    final paid = (await db.rawQuery(
            'SELECT COALESCE(SUM(amount), 0) AS t FROM inst_supplier_payments WHERE paidAt >= ? AND paidAt < ?', [from, to]))
        .first;
    var payable = 0.0;
    for (final r in await suppliers()) {
      payable += r.balance;
    }
    return PurchaseSummary(
      bills: ((b['n'] as num?) ?? 0).toInt(),
      pieces: pieces,
      total: ((b['t'] as num?) ?? 0).toDouble(),
      paid: ((paid['t'] as num?) ?? 0).toDouble(),
      payable: payable,
    );
  }

  static int _dayStart(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
  }
}

// ==================================================================== models

class InstSupplier {
  final int? id;
  final String name;
  final String phone;
  final String address;
  final String note;

  /// Pehle se jo dena tha (app shuru karne se pehle ka udhaar).
  final double openingBalance;
  final int createdAt;
  final int updatedAt;

  const InstSupplier({
    this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.note = '',
    this.openingBalance = 0,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  factory InstSupplier.fromMap(Map<String, Object?> m) => InstSupplier(
        id: (m['id'] as num?)?.toInt(),
        name: (m['name'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        openingBalance: ((m['openingBalance'] as num?) ?? 0).toDouble(),
        createdAt: ((m['createdAt'] as num?) ?? 0).toInt(),
        updatedAt: ((m['updatedAt'] as num?) ?? 0).toInt(),
      );
}

class InstSupplierRow {
  final InstSupplier supplier;
  final double purchased;
  final double paid;

  /// Wapas kiye pieces ki raqam (dena kam).
  final double returned;
  const InstSupplierRow({required this.supplier, required this.purchased, required this.paid, this.returned = 0});

  /// Hum ne kitna dena hai (minus = supplier ke paas hamara advance).
  double get balance => supplier.openingBalance + purchased - paid - returned;
}

class InstPurchase {
  final int id;
  final String billNo;
  final int supplierId;
  final String supplierName;
  final int purchaseDate;
  final double total;
  final double paid;
  final int itemCount;
  final String note;
  final String createdBy;
  final int createdAt;

  /// Is bill ke wapas kiye pieces.
  final double returned;

  const InstPurchase({
    required this.id,
    required this.billNo,
    required this.supplierId,
    this.supplierName = '',
    required this.purchaseDate,
    required this.total,
    this.paid = 0,
    this.itemCount = 0,
    this.note = '',
    this.createdBy = '',
    this.createdAt = 0,
    this.returned = 0,
  });

  double get due => total - paid - returned;

  factory InstPurchase.fromMap(Map<String, Object?> m) => InstPurchase(
        id: ((m['id'] as num?) ?? 0).toInt(),
        billNo: (m['billNo'] as String?) ?? '',
        supplierId: ((m['supplierId'] as num?) ?? 0).toInt(),
        supplierName: (m['supplierName'] as String?) ?? '',
        purchaseDate: ((m['purchaseDate'] as num?) ?? 0).toInt(),
        total: ((m['total'] as num?) ?? 0).toDouble(),
        paid: ((m['paid'] as num?) ?? 0).toDouble(),
        itemCount: ((m['itemCount'] as num?) ?? 0).toInt(),
        note: (m['note'] as String?) ?? '',
        createdBy: (m['createdBy'] as String?) ?? '',
        createdAt: ((m['createdAt'] as num?) ?? 0).toInt(),
        returned: ((m['returned'] as num?) ?? 0).toDouble(),
      );
}

/// Supplier ko wapas kiya ek piece.
class PurchaseReturn {
  final int id;
  final int supplierId;
  final int? purchaseId;
  final int itemId;
  final double amount;
  final String note;
  final String returnedBy;
  final int returnedAt;
  final String itemTitle;
  final String itemCode;

  const PurchaseReturn({
    required this.id,
    required this.supplierId,
    this.purchaseId,
    required this.itemId,
    required this.amount,
    this.note = '',
    this.returnedBy = '',
    required this.returnedAt,
    this.itemTitle = '',
    this.itemCode = '',
  });

  factory PurchaseReturn.fromMap(Map<String, Object?> m) {
    final it = InstItem.fromMap({
      'categoryId': 0,
      'brand': m['brand'],
      'model': m['model'],
      'idValues': m['idValues'],
    });
    return PurchaseReturn(
      id: ((m['id'] as num?) ?? 0).toInt(),
      supplierId: ((m['supplierId'] as num?) ?? 0).toInt(),
      purchaseId: (m['purchaseId'] as num?)?.toInt(),
      itemId: ((m['itemId'] as num?) ?? 0).toInt(),
      amount: ((m['amount'] as num?) ?? 0).toDouble(),
      note: (m['note'] as String?) ?? '',
      returnedBy: (m['returnedBy'] as String?) ?? '',
      returnedAt: ((m['returnedAt'] as num?) ?? 0).toInt(),
      itemTitle: it.title.isEmpty ? it.model : it.title,
      itemCode: it.primaryId,
    );
  }
}

class InstSupplierPayment {
  final int id;
  final int supplierId;
  final int? purchaseId;
  final double amount;
  final String method;
  final String note;
  final String paidBy;
  final int paidAt;
  final int? cashTxId;

  const InstSupplierPayment({
    required this.id,
    required this.supplierId,
    this.purchaseId,
    required this.amount,
    this.method = 'cash',
    this.note = '',
    this.paidBy = '',
    required this.paidAt,
    this.cashTxId,
  });

  factory InstSupplierPayment.fromMap(Map<String, Object?> m) => InstSupplierPayment(
        id: ((m['id'] as num?) ?? 0).toInt(),
        supplierId: ((m['supplierId'] as num?) ?? 0).toInt(),
        purchaseId: (m['purchaseId'] as num?)?.toInt(),
        amount: ((m['amount'] as num?) ?? 0).toDouble(),
        method: (m['method'] as String?) ?? 'cash',
        note: (m['note'] as String?) ?? '',
        paidBy: (m['paidBy'] as String?) ?? '',
        paidAt: ((m['paidAt'] as num?) ?? 0).toInt(),
        cashTxId: (m['cashTxId'] as num?)?.toInt(),
      );
}

/// Khate ki ek line. [bill] > 0 = khareed (dena barha), [paid] > 0 = adaigi (dena ghata).
class SupplierLedgerLine {
  final int date;
  final String label;
  final double bill;
  final double paid;
  final double balance;
  final int? purchaseId;
  final InstSupplierPayment? payment;
  final PurchaseReturn? ret;
  const SupplierLedgerLine({
    required this.date,
    required this.label,
    this.bill = 0,
    this.paid = 0,
    required this.balance,
    this.purchaseId,
    this.payment,
    this.ret,
  });
}

/// PURE (test hota hai): opening + bills + adaigi -> tareekh ke hisaab se lines, har line ke baad baqi.
/// Ek hi din par pehle bill phir adaigi.
List<SupplierLedgerLine> buildSupplierLedger(InstSupplier s, List<InstPurchase> bills, List<InstSupplierPayment> pays, Map<int, String> billNo,
    {List<PurchaseReturn> returns = const []}) {
  final events = <(int, int, SupplierLedgerLine Function(double))>[];
  for (final b in bills) {
    events.add((b.purchaseDate, 0, (double bal) => SupplierLedgerLine(
        date: b.purchaseDate, label: 'Bill ${b.billNo}', bill: b.total, balance: bal + b.total, purchaseId: b.id)));
  }
  for (final p in pays) {
    final ref = p.purchaseId == null ? '' : (billNo[p.purchaseId] ?? '');
    events.add((p.paidAt, 1, (double bal) => SupplierLedgerLine(
        date: p.paidAt,
        label: ref.isEmpty ? 'Adaigi' : 'Adaigi ($ref)',
        paid: p.amount,
        balance: bal - p.amount,
        purchaseId: p.purchaseId,
        payment: p)));
  }
  for (final r in returns) {
    events.add((r.returnedAt, 2, (double bal) => SupplierLedgerLine(
        date: r.returnedAt,
        label: 'Wapsi: ${r.itemTitle}${r.itemCode.isEmpty ? '' : ' (${r.itemCode})'}',
        paid: r.amount,
        balance: bal - r.amount,
        purchaseId: r.purchaseId,
        ret: r)));
  }
  events.sort((a, b) {
    final d = DateTime.fromMillisecondsSinceEpoch(a.$1);
    final e = DateTime.fromMillisecondsSinceEpoch(b.$1);
    final da = DateTime(d.year, d.month, d.day);
    final db = DateTime(e.year, e.month, e.day);
    final c = da.compareTo(db);
    if (c != 0) return c;
    final k = a.$2.compareTo(b.$2);
    return k != 0 ? k : a.$1.compareTo(b.$1);
  });
  final out = <SupplierLedgerLine>[];
  var bal = s.openingBalance;
  if (s.openingBalance.abs() >= 0.005) {
    out.add(SupplierLedgerLine(date: s.createdAt, label: 'Purana baqi', bill: s.openingBalance > 0 ? s.openingBalance : 0,
        paid: s.openingBalance < 0 ? -s.openingBalance : 0, balance: bal));
  }
  for (final e in events) {
    final line = e.$3(bal);
    bal = line.balance;
    out.add(line);
  }
  return out;
}

class PurchaseSummary {
  final int bills;
  final int pieces;
  final double total;
  final double paid;

  /// Aaj tak sab suppliers ka kul baqi (hum ne dena hai).
  final double payable;
  const PurchaseSummary({this.bills = 0, this.pieces = 0, this.total = 0, this.paid = 0, this.payable = 0});
}
