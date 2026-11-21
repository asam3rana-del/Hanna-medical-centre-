import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../sync/device_tag.dart';
import '../sync/sync_queue_dao.dart';
import '../sync/sync_queue_helper.dart';
import '../sync/sync_types.dart';
import 'inst_photo_sync.dart' show applyInstallmentPhotos;
import 'inst_sync_names.dart';

export 'inst_sync_names.dart';

/// Hanna Installment Step 5 — qist ke data ka Firestore sync (POS ke sync engine ke andar).
///
/// Push: har local write ke saath (usi transaction mein) [InstSync] ka `enqueueX` — POS ka `sync_queue` /
/// `SyncApi.push` hi document likhta hai (last-write-wins, tombstone delete). Pull: `SyncApi.pull` neeche wali
/// collections bhi laata hai, aur `applyRestOfServerChanges` aakhir mein [applyInstallmentChanges] chalata hai.
///
/// Local ids har device par alag — is liye har reference doosre record ki `serverId` se:
///   profile -> customerServerId, guarantor -> customerServerId, item -> categoryServerId,
///   plan -> customerServerId + itemServerId + guarantorServerIds (+ poora schedule plan ke andar),
///   payment -> planServerId + cashServerId (saath wali cash_transactions row, jo POS khud sync karta hai),
///   purchase -> supplierServerId, item -> purchaseServerId, supplier payment -> supplier/purchase/cashServerId.
/// Tasveerein sync NAHI hoti (Firebase Spark par Storage nahi) — sirf is device par.

String _s(Object? v) => v is String ? v : '';
String? _sn(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
double _d(Object? v) => v is num ? v.toDouble() : 0.0;
int _i(Object? v) => v is num ? v.toInt() : 0;

Map<String, Object?> _stamp(Map<String, Object?> m) =>
    {...m, 'updatedAt': SyncQueueHelper.nowMs(), 'branchId': SyncQueueHelper.branchId(), '_deleted': false};

Future<Map<String, Object?>?> _row(DatabaseExecutor ex, String table, String col, Object value) async {
  final r = await ex.query(table, where: '$col = ?', whereArgs: [value], limit: 1);
  return r.isEmpty ? null : Map<String, Object?>.from(r.first);
}

class InstSync {
  InstSync._();

  /// Pull apply hone ke baad (InstRepository screens ko refresh karta hai).
  static void Function()? onApplied;

  static String _own(String prefix, Map<String, Object?> row) {
    final sid = row['serverId'];
    if (sid is String && sid.trim().isNotEmpty) return sid;
    return '$prefix${DeviceTag.current}-${row['id']}';
  }

  /// Category ki id naam se (har device par pehle se bani "Mobile" ek hi doc bane, dobara nahi).
  static String categoryId(Map<String, Object?> row) {
    final sid = row['serverId'];
    if (sid is String && sid.trim().isNotEmpty) return sid;
    final key = _s(row['name']).trim().toLowerCase().replaceAll(RegExp(r'[\s/]+'), '_');
    return 'inst_category:$key';
  }

  static Future<void> _stampServerId(DatabaseExecutor ex, String table, String keyCol, Object key, String sid) =>
      ex.update(table, {'serverId': sid}, where: '$keyCol = ? AND (serverId IS NULL OR serverId != ?)', whereArgs: [key, sid]);

  /// Customer ki serverId (na ho to customer ko queue kar ke stamp — POS ka apna tareeqa).
  static Future<String?> customerServerId(DatabaseExecutor ex, int customerId) async {
    var c = await _row(ex, 'customers', 'id', customerId);
    if (c == null) return null;
    if (_sn(c['serverId']) == null) {
      await SyncQueueHelper.enqueueCustomer(ex, customerId);
      c = await _row(ex, 'customers', 'id', customerId);
    }
    return _sn(c?['serverId']);
  }

  // ================================================================ push

  static Future<void> enqueueProfile(DatabaseExecutor ex, int customerId) async {
    final p = await _row(ex, 'customer_profiles', 'customerId', customerId);
    if (p == null) return;
    final csid = await customerServerId(ex, customerId);
    if (csid == null) return;
    final eid = 'inst_profile:$csid';
    await _stampServerId(ex, 'customer_profiles', 'customerId', customerId, eid);
    await SyncQueueHelper.enqueue(ex, instProfileType, eid, 'upsert', _stamp({
      'serverId': eid,
      'customerServerId': csid,
      for (final k in const ['fatherName', 'cnic', 'phone2', 'address', 'occupation', 'workAddress', 'note']) k: _s(p[k]),
      'monthlyIncome': _d(p['monthlyIncome']),
      'createdAt': _i(p['createdAt']),
      'blockedReason': _s(p['blockedReason']),
      'blockedAt': _i(p['blockedAt']),
      'khataNo': _s(p['khataNo']),
    }));
  }

  static Future<void> enqueueGuarantor(DatabaseExecutor ex, int id) async {
    final g = await _row(ex, 'inst_guarantors', 'id', id);
    if (g == null) return;
    final csid = await customerServerId(ex, _i(g['customerId']));
    if (csid == null) return;
    final eid = _own('inst_guarantor:', g);
    await _stampServerId(ex, 'inst_guarantors', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instGuarantorType, eid, 'upsert', _stamp({
      'serverId': eid,
      'customerServerId': csid,
      for (final k in const ['name', 'fatherName', 'cnic', 'phone', 'address', 'relation', 'occupation']) k: _s(g[k]),
      'createdAt': _i(g['createdAt']),
    }));
  }

  static Future<void> enqueueCategory(DatabaseExecutor ex, int id) async {
    final c = await _row(ex, 'inst_categories', 'id', id);
    if (c == null) return;
    final eid = categoryId(c);
    await _stampServerId(ex, 'inst_categories', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instCategoryType, eid, 'upsert', _stamp({
      'serverId': eid,
      'name': _s(c['name']),
      'idFields': _s(c['idFields']),
      'sortOrder': _i(c['sortOrder']),
      'createdAt': _i(c['createdAt']),
    }));
  }

  static Future<String?> _categoryServerId(DatabaseExecutor ex, int categoryId) async {
    final c = await _row(ex, 'inst_categories', 'id', categoryId);
    if (c == null) return null;
    if (_sn(c['serverId']) == null) await enqueueCategory(ex, categoryId);
    return _sn((await _row(ex, 'inst_categories', 'id', categoryId))?['serverId']);
  }

  static Future<String?> itemServerId(DatabaseExecutor ex, int itemId) async {
    final it = await _row(ex, 'inst_items', 'id', itemId);
    if (it == null) return null;
    final sid = _sn(it['serverId']);
    if (sid != null) return sid;
    await enqueueItem(ex, itemId);
    return _sn((await _row(ex, 'inst_items', 'id', itemId))?['serverId']);
  }

  static Future<void> enqueueItem(DatabaseExecutor ex, int id) async {
    final it = await _row(ex, 'inst_items', 'id', id);
    if (it == null) return;
    final cat = await _categoryServerId(ex, _i(it['categoryId']));
    final pur = it['purchaseId'] is num ? await purchaseServerId(ex, _i(it['purchaseId'])) : null;
    final eid = _own('inst_item:', it);
    await _stampServerId(ex, 'inst_items', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instItemType, eid, 'upsert', _stamp({
      'serverId': eid,
      'categoryServerId': cat,
      'purchaseServerId': pur,
      for (final k in const ['brand', 'model', 'color', 'idValues', 'supplier', 'note', 'status']) k: _s(it[k]),
      'costPrice': _d(it['costPrice']),
      'cashPrice': _d(it['cashPrice']),
      'warrantyMonths': _i(it['warrantyMonths']),
      'purchaseDate': _i(it['purchaseDate']),
      'createdAt': _i(it['createdAt']),
    }));
  }

  static Future<String?> planServerId(DatabaseExecutor ex, int planId) async {
    final p = await _row(ex, 'inst_plans', 'id', planId);
    if (p == null) return null;
    final sid = _sn(p['serverId']);
    if (sid != null) return sid;
    await enqueuePlan(ex, planId);
    return _sn((await _row(ex, 'inst_plans', 'id', planId))?['serverId']);
  }

  static Future<void> enqueuePlan(DatabaseExecutor ex, int id) async {
    final p = await _row(ex, 'inst_plans', 'id', id);
    if (p == null) return;
    final csid = await customerServerId(ex, _i(p['customerId']));
    final isid = await itemServerId(ex, _i(p['itemId']));
    if (csid == null || isid == null) return;
    final gIds = <String>[];
    try {
      final raw = jsonDecode(_s(p['guarantorIds']));
      if (raw is List) {
        for (final g in raw) {
          if (g is! num) continue;
          final gr = await _row(ex, 'inst_guarantors', 'id', g.toInt());
          if (gr == null) continue;
          if (_sn(gr['serverId']) == null) await enqueueGuarantor(ex, g.toInt());
          final sid = _sn((await _row(ex, 'inst_guarantors', 'id', g.toInt()))?['serverId']);
          if (sid != null) gIds.add(sid);
        }
      }
    } catch (_) {}
    final sched = [
      for (final r in await ex.query('inst_schedule', where: 'planId = ?', whereArgs: [id], orderBy: 'seq'))
        {'seq': _i(r['seq']), 'dueDate': _i(r['dueDate']), 'amount': _d(r['amount'])}
    ];
    final secs = [
      for (final r in await ex.query('inst_securities', where: 'planId = ?', whereArgs: [id], orderBy: 'id'))
        {
          for (final k in const ['kind', 'number', 'bank', 'note']) k: _s(r[k]),
          'amount': _d(r['amount']),
          'returnedAt': _i(r['returnedAt']),
          'createdAt': _i(r['createdAt']),
        }
    ];
    final eid = _own('inst_plan:', p);
    await _stampServerId(ex, 'inst_plans', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instPlanType, eid, 'upsert', _stamp({
      'serverId': eid,
      'customerServerId': csid,
      'itemServerId': isid,
      'guarantorServerIds': gIds,
      'schedule': sched,
      'securities': secs,
      for (final k in const ['planNo', 'profitMode', 'frequency', 'status', 'note', 'createdBy']) k: _s(p[k]),
      for (final k in const ['cashPrice', 'costPrice', 'advance', 'profitValue', 'profit', 'totalPrice', 'installmentTotal', 'lateFee'])
        k: _d(p[k]),
      for (final k in const ['count', 'firstDueDate', 'roundTo', 'graceDays', 'createdAt', 'closedAt']) k: _i(p[k]),
    }));
  }

  static Future<void> enqueuePayment(DatabaseExecutor ex, int id) async {
    final pay = await _row(ex, 'inst_payments', 'id', id);
    if (pay == null) return;
    final psid = await planServerId(ex, _i(pay['planId']));
    if (psid == null) return;
    String? cashSid;
    final cashId = pay['cashTxId'];
    if (cashId is num) {
      final cash = await _row(ex, 'cash_transactions', 'id', cashId.toInt());
      if (cash != null) cashSid = SyncQueueHelper.cashTransactionEntityId(cash);
    }
    final eid = _own('inst_payment:', pay);
    await _stampServerId(ex, 'inst_payments', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instPaymentType, eid, 'upsert', _stamp({
      'serverId': eid,
      'planServerId': psid,
      'cashServerId': cashSid,
      for (final k in const ['kind', 'method', 'note', 'receivedBy']) k: _s(pay[k]),
      'amount': _d(pay['amount']),
      'fine': _d(pay['fine']),
      'paidAt': _i(pay['paidAt']),
      'createdAt': _i(pay['createdAt']),
    }));
  }

  static Future<void> enqueuePriceChange(DatabaseExecutor ex, int id) async {
    final r = await _row(ex, 'inst_price_changes', 'id', id);
    if (r == null) return;
    final isid = await itemServerId(ex, _i(r['itemId']));
    if (isid == null) return;
    final eid = _own('inst_price_change:', r);
    await _stampServerId(ex, 'inst_price_changes', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instPriceChangeType, eid, 'upsert', _stamp({
      'serverId': eid,
      'itemServerId': isid,
      for (final k in const ['oldCash', 'newCash', 'oldCost', 'newCost']) k: _d(r[k]),
      'note': _s(r['note']),
      'changedBy': _s(r['changedBy']),
      'changedAt': _i(r['changedAt']),
    }));
  }

  // ---------------------------------------------------------------- khareed (v41)

  static Future<void> enqueueSupplier(DatabaseExecutor ex, int id) async {
    final r = await _row(ex, 'inst_suppliers', 'id', id);
    if (r == null) return;
    final eid = _own('inst_supplier:', r);
    await _stampServerId(ex, 'inst_suppliers', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instSupplierType, eid, 'upsert', _stamp({
      'serverId': eid,
      for (final k in const ['name', 'phone', 'address', 'note']) k: _s(r[k]),
      'openingBalance': _d(r['openingBalance']),
      'createdAt': _i(r['createdAt']),
    }));
  }

  static Future<String?> supplierServerId(DatabaseExecutor ex, int supplierId) async {
    final r = await _row(ex, 'inst_suppliers', 'id', supplierId);
    if (r == null) return null;
    if (_sn(r['serverId']) == null) await enqueueSupplier(ex, supplierId);
    return _sn((await _row(ex, 'inst_suppliers', 'id', supplierId))?['serverId']);
  }

  static Future<void> enqueuePurchase(DatabaseExecutor ex, int id) async {
    final r = await _row(ex, 'inst_purchases', 'id', id);
    if (r == null) return;
    final ssid = await supplierServerId(ex, _i(r['supplierId']));
    if (ssid == null) return;
    final eid = _own('inst_purchase:', r);
    await _stampServerId(ex, 'inst_purchases', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instPurchaseType, eid, 'upsert', _stamp({
      'serverId': eid,
      'supplierServerId': ssid,
      for (final k in const ['billNo', 'note', 'createdBy']) k: _s(r[k]),
      'total': _d(r['total']),
      'purchaseDate': _i(r['purchaseDate']),
      'createdAt': _i(r['createdAt']),
    }));
  }

  static Future<String?> purchaseServerId(DatabaseExecutor ex, int purchaseId) async {
    final r = await _row(ex, 'inst_purchases', 'id', purchaseId);
    if (r == null) return null;
    if (_sn(r['serverId']) == null) await enqueuePurchase(ex, purchaseId);
    return _sn((await _row(ex, 'inst_purchases', 'id', purchaseId))?['serverId']);
  }

  static Future<void> enqueueSupplierPayment(DatabaseExecutor ex, int id) async {
    final r = await _row(ex, 'inst_supplier_payments', 'id', id);
    if (r == null) return;
    final ssid = await supplierServerId(ex, _i(r['supplierId']));
    if (ssid == null) return;
    final psid = r['purchaseId'] is num ? await purchaseServerId(ex, _i(r['purchaseId'])) : null;
    String? cashSid;
    final cashId = r['cashTxId'];
    if (cashId is num) {
      final cash = await _row(ex, 'cash_transactions', 'id', cashId.toInt());
      if (cash != null) cashSid = SyncQueueHelper.cashTransactionEntityId(cash);
    }
    final eid = _own('inst_supplier_payment:', r);
    await _stampServerId(ex, 'inst_supplier_payments', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instSupplierPaymentType, eid, 'upsert', _stamp({
      'serverId': eid,
      'supplierServerId': ssid,
      'purchaseServerId': psid,
      'cashServerId': cashSid,
      for (final k in const ['method', 'note', 'paidBy']) k: _s(r[k]),
      'amount': _d(r['amount']),
      'paidAt': _i(r['paidAt']),
      'createdAt': _i(r['createdAt']),
    }));
  }

  // ---------------------------------------------------------------- naqd sale (v42)

  static Future<void> enqueueCashSale(DatabaseExecutor ex, int id) async {
    final r = await _row(ex, 'inst_cash_sales', 'id', id);
    if (r == null) return;
    final isid = await itemServerId(ex, _i(r['itemId']));
    if (isid == null) return;
    String? cashSid;
    final cashId = r['cashTxId'];
    if (cashId is num) {
      final cash = await _row(ex, 'cash_transactions', 'id', cashId.toInt());
      if (cash != null) cashSid = SyncQueueHelper.cashTransactionEntityId(cash);
    }
    final csid = r['customerId'] is num ? await customerServerId(ex, _i(r['customerId'])) : null;
    String? refundSid;
    final refundId = r['refundCashTxId'];
    if (refundId is num) {
      final cash = await _row(ex, 'cash_transactions', 'id', refundId.toInt());
      if (cash != null) refundSid = SyncQueueHelper.cashTransactionEntityId(cash);
    }
    final eid = _own('inst_cash_sale:', r);
    await _stampServerId(ex, 'inst_cash_sales', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instCashSaleType, eid, 'upsert', _stamp({
      'serverId': eid,
      'itemServerId': isid,
      'customerServerId': csid,
      'cashServerId': cashSid,
      for (final k in const ['saleNo', 'customerName', 'phone', 'method', 'note', 'soldBy']) k: _s(r[k]),
      'price': _d(r['price']),
      'costPrice': _d(r['costPrice']),
      'soldAt': _i(r['soldAt']),
      'createdAt': _i(r['createdAt']),
      'returnedAt': r['returnedAt'] is num ? _i(r['returnedAt']) : null,
      'refund': _d(r['refund']),
      'returnNote': _s(r['returnNote']),
      'refundCashServerId': refundSid,
    }));
  }

  static Future<void> enqueuePurchaseReturn(DatabaseExecutor ex, int id) async {
    final r = await _row(ex, 'inst_purchase_returns', 'id', id);
    if (r == null) return;
    final ssid = await supplierServerId(ex, _i(r['supplierId']));
    final isid = await itemServerId(ex, _i(r['itemId']));
    if (ssid == null || isid == null) return;
    final psid = r['purchaseId'] is num ? await purchaseServerId(ex, _i(r['purchaseId'])) : null;
    final eid = _own('inst_purchase_return:', r);
    await _stampServerId(ex, 'inst_purchase_returns', 'id', id, eid);
    await SyncQueueHelper.enqueue(ex, instPurchaseReturnType, eid, 'upsert', _stamp({
      'serverId': eid,
      'supplierServerId': ssid,
      'purchaseServerId': psid,
      'itemServerId': isid,
      'amount': _d(r['amount']),
      'note': _s(r['note']),
      'returnedBy': _s(r['returnedBy']),
      'returnedAt': _i(r['returnedAt']),
      'createdAt': _i(r['createdAt']),
    }));
  }

  /// Delete se PEHLE bulayein (row se serverId chahiye). serverId na ho (kabhi push hi nahi hua) to kuch nahi.
  static Future<void> enqueueDeleteRow(DatabaseExecutor ex, String type, String table, String keyCol, Object key) async {
    final r = await _row(ex, table, keyCol, key);
    final sid = _sn(r?['serverId']);
    if (sid == null) return;
    await SyncQueueHelper.enqueueDelete(ex, type, sid);
  }

  /// "Force full push": sab qist data dobara queue (parent pehle).
  static Future<void> enqueueAll(DatabaseExecutor ex) async {
    if ((await ex.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_plans'")).isEmpty) return;
    for (final r in await ex.query('inst_categories', columns: ['id'])) {
      await enqueueCategory(ex, _i(r['id']));
    }
    for (final r in await ex.query('customer_profiles', columns: ['customerId'])) {
      await enqueueProfile(ex, _i(r['customerId']));
    }
    for (final r in await ex.query('inst_guarantors', columns: ['id'])) {
      await enqueueGuarantor(ex, _i(r['id']));
    }
    final hasPurchases = (await ex.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_purchases'")).isNotEmpty;
    if (hasPurchases) {
      for (final r in await ex.query('inst_suppliers', columns: ['id'])) {
        await enqueueSupplier(ex, _i(r['id']));
      }
      for (final r in await ex.query('inst_purchases', columns: ['id'])) {
        await enqueuePurchase(ex, _i(r['id']));
      }
    }
    for (final r in await ex.query('inst_items', columns: ['id'])) {
      await enqueueItem(ex, _i(r['id']));
    }
    if (hasPurchases) {
      for (final r in await ex.query('inst_supplier_payments', columns: ['id'])) {
        await enqueueSupplierPayment(ex, _i(r['id']));
      }
    }
    if ((await ex.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_cash_sales'")).isNotEmpty) {
      for (final r in await ex.query('inst_cash_sales', columns: ['id'])) {
        await enqueueCashSale(ex, _i(r['id']));
      }
    }
    if ((await ex.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_purchase_returns'")).isNotEmpty) {
      for (final r in await ex.query('inst_purchase_returns', columns: ['id'])) {
        await enqueuePurchaseReturn(ex, _i(r['id']));
      }
    }
    for (final r in await ex.query('inst_plans', columns: ['id'])) {
      await enqueuePlan(ex, _i(r['id']));
    }
    for (final r in await ex.query('inst_payments', columns: ['id'])) {
      await enqueuePayment(ex, _i(r['id']));
    }
    if ((await ex.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_price_changes'")).isNotEmpty) {
      for (final r in await ex.query('inst_price_changes', columns: ['id'])) {
        await enqueuePriceChange(ex, _i(r['id']));
      }
    }
  }
}

// ================================================================== pull / apply

Future<int?> _localIdBySid(DatabaseExecutor db, String table, String sid, {String idCol = 'id'}) async {
  final r = await _row(db, table, 'serverId', sid);
  return r == null ? null : _i(r[idCol]);
}

/// [docs] = collection -> documents (PullResult.installment). Ek hi transaction mein (db = txn).
Future<void> applyInstallmentChanges(DatabaseExecutor db, Map<String, List<SyncDoc>> docs, {required int Function() nowMs}) async {
  if (docs.values.every((l) => l.isEmpty)) return;
  if ((await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_plans'")).isEmpty) return;
  final q = SyncQueueDao(db);
  List<SyncDoc> of(String c) => docs[c] ?? const [];
  Future<bool> pending(String type, String sid) async => await q.pendingCountForEntity(type, sid) > 0;

  // ---- categories (naam se bhi milate hain: dono device par pehle se bani "Mobile")
  for (final d in of('inst_categories')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instCategoryType, sid)) continue;
    var local = await _row(db, 'inst_categories', 'serverId', sid);
    if (d['_deleted'] == true) {
      if (local != null) {
        final used = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_items WHERE categoryId = ?', [local['id']])) ?? 0;
        if (used == 0) await db.delete('inst_categories', where: 'id = ?', whereArgs: [local['id']]);
      }
      continue;
    }
    final name = _s(d['name']).trim();
    if (name.isEmpty) continue;
    local ??= (await db.rawQuery(
            'SELECT * FROM inst_categories WHERE LOWER(TRIM(name)) = ? AND (serverId IS NULL OR serverId = \'\') LIMIT 1',
            [name.toLowerCase()]))
        .firstOrNull;
    final values = {
      'name': name,
      'idFields': _s(d['idFields']).isEmpty ? '[]' : _s(d['idFields']),
      'sortOrder': _i(d['sortOrder']),
      'updatedAt': _i(d['updatedAt']),
      'serverId': sid,
    };
    if (local == null) {
      await db.insert('inst_categories', {...values, 'createdAt': _i(d['createdAt']) == 0 ? nowMs() : _i(d['createdAt'])});
    } else {
      await db.update('inst_categories', values, where: 'id = ?', whereArgs: [local['id']]);
    }
  }

  final hasPurchases = (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_purchases'")).isNotEmpty;

  // ---- suppliers (khareed)
  if (hasPurchases) {
    for (final d in of('inst_suppliers')) {
      final sid = _sn(d['serverId']);
      if (sid == null || await pending(instSupplierType, sid)) continue;
      final localId = await _localIdBySid(db, 'inst_suppliers', sid);
      if (d['_deleted'] == true) {
        if (localId != null) {
          final used = (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_purchases WHERE supplierId = ?', [localId])) ?? 0) +
              (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_supplier_payments WHERE supplierId = ?', [localId])) ?? 0);
          if (used == 0) await db.delete('inst_suppliers', where: 'id = ?', whereArgs: [localId]);
        }
        continue;
      }
      final name = _s(d['name']).trim();
      if (name.isEmpty) continue;
      final values = <String, Object?>{
        'name': name,
        for (final k in const ['phone', 'address', 'note']) k: _s(d[k]),
        'openingBalance': _d(d['openingBalance']),
        'updatedAt': _i(d['updatedAt']),
      };
      if (localId == null) {
        await db.insert('inst_suppliers', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
      } else {
        await db.update('inst_suppliers', values, where: 'id = ?', whereArgs: [localId]);
      }
    }

    // ---- khareed ke bill
    for (final d in of('inst_purchases')) {
      final sid = _sn(d['serverId']);
      if (sid == null || await pending(instPurchaseType, sid)) continue;
      final localId = await _localIdBySid(db, 'inst_purchases', sid);
      if (d['_deleted'] == true) {
        if (localId != null) {
          await db.update('inst_items', {'purchaseId': null}, where: 'purchaseId = ?', whereArgs: [localId]);
          await db.update('inst_supplier_payments', {'purchaseId': null}, where: 'purchaseId = ?', whereArgs: [localId]);
          await db.delete('inst_purchases', where: 'id = ?', whereArgs: [localId]);
        }
        continue;
      }
      final supId = await _localIdBySid(db, 'inst_suppliers', _s(d['supplierServerId']));
      if (supId == null) continue;
      final values = <String, Object?>{
        'supplierId': supId,
        for (final k in const ['billNo', 'note', 'createdBy']) k: _s(d[k]),
        'total': _d(d['total']),
        'purchaseDate': _i(d['purchaseDate']),
        'updatedAt': _i(d['updatedAt']),
      };
      if (localId == null) {
        await db.insert('inst_purchases', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
      } else {
        await db.update('inst_purchases', values, where: 'id = ?', whereArgs: [localId]);
      }
    }
  }

  // ---- profiles
  for (final d in of('inst_customer_profiles')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instProfileType, sid)) continue;
    final cid = await _localIdBySid(db, 'customers', _s(d['customerServerId']));
    if (d['_deleted'] == true) {
      if (cid != null) await db.delete('customer_profiles', where: 'customerId = ?', whereArgs: [cid]);
      continue;
    }
    if (cid == null) continue; // customer abhi is device par nahi
    final values = <String, Object?>{
      for (final k in const ['fatherName', 'cnic', 'phone2', 'address', 'occupation', 'workAddress', 'note']) k: _s(d[k]),
      'monthlyIncome': _d(d['monthlyIncome']),
      'blockedReason': _s(d['blockedReason']),
      'blockedAt': _i(d['blockedAt']),
      'khataNo': _s(d['khataNo']),
      'updatedAt': _i(d['updatedAt']),
      'serverId': sid,
    };
    if (await _row(db, 'customer_profiles', 'customerId', cid) == null) {
      await db.insert('customer_profiles', {...values, 'customerId': cid, 'createdAt': _i(d['createdAt'])});
    } else {
      await db.update('customer_profiles', values, where: 'customerId = ?', whereArgs: [cid]);
    }
  }

  // ---- guarantors
  for (final d in of('inst_guarantors')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instGuarantorType, sid)) continue;
    final localId = await _localIdBySid(db, 'inst_guarantors', sid);
    if (d['_deleted'] == true) {
      if (localId != null) await db.delete('inst_guarantors', where: 'id = ?', whereArgs: [localId]);
      continue;
    }
    final cid = await _localIdBySid(db, 'customers', _s(d['customerServerId']));
    final name = _s(d['name']).trim();
    if (cid == null || name.isEmpty) continue;
    final values = <String, Object?>{
      'customerId': cid,
      for (final k in const ['name', 'fatherName', 'cnic', 'phone', 'address', 'relation', 'occupation']) k: _s(d[k]),
      'updatedAt': _i(d['updatedAt']),
    };
    if (localId == null) {
      await db.insert('inst_guarantors', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
    } else {
      await db.update('inst_guarantors', values, where: 'id = ?', whereArgs: [localId]);
    }
  }

  // ---- items
  for (final d in of('inst_items')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instItemType, sid)) continue;
    final localId = await _localIdBySid(db, 'inst_items', sid);
    if (d['_deleted'] == true) {
      if (localId != null) {
        final used = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_plans WHERE itemId = ?', [localId])) ?? 0;
        if (used == 0) await db.delete('inst_items', where: 'id = ?', whereArgs: [localId]);
      }
      continue;
    }
    final catSid = _sn(d['categoryServerId']);
    var catId = catSid == null ? null : await _localIdBySid(db, 'inst_categories', catSid);
    catId ??= _i((await db.rawQuery('SELECT id FROM inst_categories ORDER BY sortOrder LIMIT 1')).firstOrNull?['id']);
    final model = _s(d['model']).trim();
    if (model.isEmpty) continue;
    final status = _s(d['status']);
    final values = <String, Object?>{
      'categoryId': catId,
      for (final k in const ['brand', 'color', 'supplier', 'note']) k: _s(d[k]),
      'model': model,
      'idValues': _s(d['idValues']).isEmpty ? '{}' : _s(d['idValues']),
      'status': const {'in_stock', 'sold', 'returned', 'repossessed'}.contains(status) ? status : 'in_stock',
      'costPrice': _d(d['costPrice']),
      'cashPrice': _d(d['cashPrice']),
      'warrantyMonths': _i(d['warrantyMonths']),
      'purchaseDate': _i(d['purchaseDate']),
      'updatedAt': _i(d['updatedAt']),
    };
    final purSid = _sn(d['purchaseServerId']);
    if (hasPurchases && purSid != null) {
      final purId = await _localIdBySid(db, 'inst_purchases', purSid);
      if (purId != null) values['purchaseId'] = purId;
    }
    if (localId == null) {
      await db.insert('inst_items', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
    } else {
      await db.update('inst_items', values, where: 'id = ?', whereArgs: [localId]);
    }
  }

  // ---- plans (+ schedule)
  for (final d in of('inst_plans')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instPlanType, sid)) continue;
    final localId = await _localIdBySid(db, 'inst_plans', sid);
    if (d['_deleted'] == true) {
      if (localId != null) {
        await db.delete('inst_payments', where: 'planId = ?', whereArgs: [localId]);
        await db.delete('inst_schedule', where: 'planId = ?', whereArgs: [localId]);
        await db.delete('inst_plans', where: 'id = ?', whereArgs: [localId]);
      }
      continue;
    }
    final cid = await _localIdBySid(db, 'customers', _s(d['customerServerId']));
    final iid = await _localIdBySid(db, 'inst_items', _s(d['itemServerId']));
    if (cid == null || iid == null) continue;
    final gLocal = <int>[];
    final gs = d['guarantorServerIds'];
    if (gs is List) {
      for (final g in gs) {
        if (g is! String) continue;
        final id = await _localIdBySid(db, 'inst_guarantors', g);
        if (id != null) gLocal.add(id);
      }
    }
    final values = <String, Object?>{
      'customerId': cid,
      'itemId': iid,
      'guarantorIds': jsonEncode(gLocal),
      for (final k in const ['planNo', 'profitMode', 'frequency', 'status', 'note', 'createdBy']) k: _s(d[k]),
      for (final k in const ['cashPrice', 'costPrice', 'advance', 'profitValue', 'profit', 'totalPrice', 'installmentTotal', 'lateFee'])
        k: _d(d[k]),
      for (final k in const ['count', 'firstDueDate', 'roundTo', 'graceDays', 'closedAt']) k: _i(d[k]),
      'updatedAt': _i(d['updatedAt']),
    };
    final int planId;
    if (localId == null) {
      planId = await db.insert('inst_plans', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
    } else {
      planId = localId;
      await db.update('inst_plans', values, where: 'id = ?', whereArgs: [localId]);
    }
    final sched = d['schedule'];
    if (sched is List && sched.isNotEmpty) {
      await db.delete('inst_schedule', where: 'planId = ?', whereArgs: [planId]);
      for (final s in sched) {
        if (s is! Map) continue;
        await db.insert('inst_schedule', {'planId': planId, 'seq': _i(s['seq']), 'dueDate': _i(s['dueDate']), 'amount': _d(s['amount'])},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    // Security cheque / kaghzat (v46): purane doc mein field nahi hota => local wahi rehte hain.
    final secs = d['securities'];
    if (secs is List) {
      await db.delete('inst_securities', where: 'planId = ?', whereArgs: [planId]);
      for (final s in secs) {
        if (s is! Map) continue;
        await db.insert('inst_securities', {
          'planId': planId,
          for (final k in const ['kind', 'number', 'bank', 'note']) k: _s(s[k]),
          'amount': _d(s['amount']),
          'returnedAt': _i(s['returnedAt']),
          'createdAt': _i(s['createdAt']),
        });
      }
    }
  }

  // ---- payments (cash row POS sync se pehle hi aa chuki hoti hai: cashServerId se jodo)
  for (final d in of('inst_payments')) {
    final sid = _sn(d['serverId']);
    if (sid == null || await pending(instPaymentType, sid)) continue;
    final localId = await _localIdBySid(db, 'inst_payments', sid);
    if (d['_deleted'] == true) {
      if (localId != null) await db.delete('inst_payments', where: 'id = ?', whereArgs: [localId]);
      continue;
    }
    final pid = await _localIdBySid(db, 'inst_plans', _s(d['planServerId']));
    if (pid == null) continue;
    final cashSid = _sn(d['cashServerId']);
    final cashId = cashSid == null ? null : await _localIdBySid(db, 'cash_transactions', cashSid);
    final k0 = _s(d['kind']);
    final kind = k0 == 'advance' ? 'advance' : (k0 == 'discount' ? 'discount' : 'installment');
    final values = <String, Object?>{
      'planId': pid,
      'kind': kind,
      'amount': _d(d['amount']),
      'fine': _d(d['fine']),
      'method': _s(d['method']) == 'bank' ? 'bank' : 'cash',
      'note': _s(d['note']),
      'receivedBy': _s(d['receivedBy']),
      'paidAt': _i(d['paidAt']),
      'cashTxId': cashId,
    };
    if (localId == null) {
      await db.insert('inst_payments', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
    } else {
      await db.update('inst_payments', values, where: 'id = ?', whereArgs: [localId]);
    }
  }
  // ---- naqd sale (item upar aa chuka; cash IN row POS sync se: cashServerId se jodo)
  final saleDocs = of('inst_cash_sales');
  if (saleDocs.isNotEmpty &&
      (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_cash_sales'")).isNotEmpty) {
    for (final d in saleDocs) {
      final sid = _sn(d['serverId']);
      if (sid == null || await pending(instCashSaleType, sid)) continue;
      final localId = await _localIdBySid(db, 'inst_cash_sales', sid);
      if (d['_deleted'] == true) {
        if (localId != null) await db.delete('inst_cash_sales', where: 'id = ?', whereArgs: [localId]);
        continue;
      }
      final iid = await _localIdBySid(db, 'inst_items', _s(d['itemServerId']));
      if (iid == null) continue;
      final cashSid = _sn(d['cashServerId']);
      final cashId = cashSid == null ? null : await _localIdBySid(db, 'cash_transactions', cashSid);
      final cusSid = _sn(d['customerServerId']);
      final values = <String, Object?>{
        'itemId': iid,
        'customerId': cusSid == null ? null : await _localIdBySid(db, 'customers', cusSid),
        for (final k in const ['saleNo', 'customerName', 'phone', 'note', 'soldBy']) k: _s(d[k]),
        'method': _s(d['method']) == 'bank' ? 'bank' : 'cash',
        'price': _d(d['price']),
        'costPrice': _d(d['costPrice']),
        'soldAt': _i(d['soldAt']),
        'cashTxId': cashId,
        'returnedAt': d['returnedAt'] is num ? (d['returnedAt'] as num).toInt() : null,
        'refund': _d(d['refund']),
        'returnNote': _s(d['returnNote']),
        'refundCashTxId': _sn(d['refundCashServerId']) == null
            ? null
            : await _localIdBySid(db, 'cash_transactions', _s(d['refundCashServerId'])),
        'updatedAt': _i(d['updatedAt']),
      };
      if (localId == null) {
        await db.insert('inst_cash_sales', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
      } else {
        await db.update('inst_cash_sales', values, where: 'id = ?', whereArgs: [localId]);
      }
    }
  }

  // ---- supplier ko wapsi (item + bill upar aa chuke)
  final retDocs = of('inst_purchase_returns');
  if (retDocs.isNotEmpty &&
      (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_purchase_returns'")).isNotEmpty) {
    for (final d in retDocs) {
      final sid = _sn(d['serverId']);
      if (sid == null || await pending(instPurchaseReturnType, sid)) continue;
      final localId = await _localIdBySid(db, 'inst_purchase_returns', sid);
      if (d['_deleted'] == true) {
        if (localId != null) await db.delete('inst_purchase_returns', where: 'id = ?', whereArgs: [localId]);
        continue;
      }
      final supId = await _localIdBySid(db, 'inst_suppliers', _s(d['supplierServerId']));
      final iid = await _localIdBySid(db, 'inst_items', _s(d['itemServerId']));
      if (supId == null || iid == null) continue;
      final purSid = _sn(d['purchaseServerId']);
      final values = <String, Object?>{
        'supplierId': supId,
        'purchaseId': purSid == null ? null : await _localIdBySid(db, 'inst_purchases', purSid),
        'itemId': iid,
        'amount': _d(d['amount']),
        'note': _s(d['note']),
        'returnedBy': _s(d['returnedBy']),
        'returnedAt': _i(d['returnedAt']),
        'updatedAt': _i(d['updatedAt']),
      };
      if (localId == null) {
        await db.insert('inst_purchase_returns', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
      } else {
        await db.update('inst_purchase_returns', values, where: 'id = ?', whereArgs: [localId]);
      }
    }
  }

  // ---- supplier ko adaigi (cash OUT row POS sync se: cashServerId se jodo)
  if (hasPurchases) {
    for (final d in of('inst_supplier_payments')) {
      final sid = _sn(d['serverId']);
      if (sid == null || await pending(instSupplierPaymentType, sid)) continue;
      final localId = await _localIdBySid(db, 'inst_supplier_payments', sid);
      if (d['_deleted'] == true) {
        if (localId != null) await db.delete('inst_supplier_payments', where: 'id = ?', whereArgs: [localId]);
        continue;
      }
      final supId = await _localIdBySid(db, 'inst_suppliers', _s(d['supplierServerId']));
      if (supId == null) continue;
      final purSid = _sn(d['purchaseServerId']);
      final purId = purSid == null ? null : await _localIdBySid(db, 'inst_purchases', purSid);
      final cashSid = _sn(d['cashServerId']);
      final cashId = cashSid == null ? null : await _localIdBySid(db, 'cash_transactions', cashSid);
      final values = <String, Object?>{
        'supplierId': supId,
        'purchaseId': purId,
        'amount': _d(d['amount']),
        'method': _s(d['method']) == 'bank' ? 'bank' : 'cash',
        'note': _s(d['note']),
        'paidBy': _s(d['paidBy']),
        'paidAt': _i(d['paidAt']),
        'cashTxId': cashId,
        'updatedAt': _i(d['updatedAt']),
      };
      if (localId == null) {
        await db.insert('inst_supplier_payments', {...values, 'createdAt': _i(d['createdAt']), 'serverId': sid});
      } else {
        await db.update('inst_supplier_payments', values, where: 'id = ?', whereArgs: [localId]);
      }
    }
  }

  // ---- rate tabdeeli ka record (sirf tareekh; item ki nayi qeemat item doc se aati hai)
  final priceDocs = of('inst_price_changes');
  if (priceDocs.isNotEmpty &&
      (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_price_changes'")).isNotEmpty) {
    for (final d in priceDocs) {
      final sid = _sn(d['serverId']);
      if (sid == null || await pending(instPriceChangeType, sid)) continue;
      final localId = await _localIdBySid(db, 'inst_price_changes', sid);
      if (d['_deleted'] == true) {
        if (localId != null) await db.delete('inst_price_changes', where: 'id = ?', whereArgs: [localId]);
        continue;
      }
      final iid = await _localIdBySid(db, 'inst_items', _s(d['itemServerId']));
      if (iid == null) continue;
      final values = <String, Object?>{
        'itemId': iid,
        for (final k in const ['oldCash', 'newCash', 'oldCost', 'newCost']) k: _d(d[k]),
        'note': _s(d['note']),
        'changedBy': _s(d['changedBy']),
        'changedAt': _i(d['changedAt']),
      };
      if (localId == null) {
        await db.insert('inst_price_changes', {...values, 'serverId': sid});
      } else {
        await db.update('inst_price_changes', values, where: 'id = ?', whereArgs: [localId]);
      }
    }
  }

  // ---- tasveerein (files; customers / guarantors upar aa chuke)
  await applyInstallmentPhotos(db, of('inst_photos'));
  InstSync.onApplied?.call();
}
