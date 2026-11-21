import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../app_info.dart';
import '../db/app_database.dart';
import '../license/license_service.dart';
import '../models/misc_entities.dart' show CashTransaction;
import '../services/session.dart';
import '../sync/device_tag.dart';
import '../sync/sync_queue_helper.dart';
import 'inst_models.dart';
import 'inst_repository.dart';
import 'inst_sync.dart';

/// Naqd (cash) sale: stock ka piece bina qist ke bikta hai.
/// Piece `sold`, `cash_transactions` IN row (reference `inst-sale:<id>`), sale ka record (bechte waqt ki khareed qeemat
/// ke saath — munafa ke liye). Wapas (ghalat entry): piece dobara stock mein, cash row hat'ti hai (sirf Admin / Manager).
class InstCashSaleRepository {
  InstCashSaleRepository._();
  static final InstCashSaleRepository instance = InstCashSaleRepository._();

  int _now() => DateTime.now().millisecondsSinceEpoch;
  void _changed() => InstRepository.instance.changes.value++;

  /// Wapas: sale id.
  Future<int> sell({
    required int itemId,
    required double price,
    int? customerId,
    String customerName = '',
    String phone = '',
    String method = 'cash',
    String note = '',
    int? soldAt,
  }) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    if (!price.isFinite || price <= 0) throw ArgumentError('Qeemat likhein.');
    if (method != 'cash' && method != 'bank') throw ArgumentError('Cash ya Bank chunein.');
    if (!phoneValid(phone)) throw ArgumentError('Phone number theek nahi (03xx xxxxxxx).');
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_items', where: 'id = ?', whereArgs: [itemId], limit: 1);
    if (rows.isEmpty) throw ArgumentError('Piece nahi mila.');
    final item = InstItem.fromMap(rows.first);
    if (!item.inStock) throw ArgumentError('Ye piece stock mein nahi (bik chuka / qist par).');
    final now = _now();
    final when = soldAt ?? now;
    final title = item.title.isEmpty ? item.model : item.title;
    final id = await db.transaction((txn) async {
      final sid = await txn.insert('inst_cash_sales', {
        'saleNo': '',
        'itemId': itemId,
        'customerId': customerId,
        'customerName': customerName.trim(),
        'phone': phone.trim(),
        'price': price,
        'costPrice': item.costPrice,
        'method': method,
        'note': note.trim(),
        'soldBy': Session.username ?? '',
        'soldAt': when,
        'createdAt': now,
        'updatedAt': now,
      });
      // Device tag ke 2 harf: do devices ke number na takrayein (N-7F0012).
      final tag = DeviceTag.current.length >= 2 ? DeviceTag.current.substring(0, 2) : DeviceTag.current;
      final saleNo = 'N-$tag${sid.toString().padLeft(4, '0')}';
      await txn.update('inst_items', {'status': itemSold, 'updatedAt': now}, where: 'id = ?', whereArgs: [itemId]);
      await InstSync.enqueueItem(txn, itemId);
      final cash = CashTransaction(
        type: 'IN',
        method: method,
        amount: price,
        reason: 'Naqd sale: $saleNo $title',
        reference: 'inst-sale:$sid',
        createdAt: when,
        updatedAt: now,
      );
      final cashId = await txn.insert('cash_transactions', cash.toMap()..remove('id'));
      await SyncQueueHelper.enqueueCashTransaction(txn, cashId);
      await txn.update('inst_cash_sales', {'saleNo': saleNo, 'cashTxId': cashId}, where: 'id = ?', whereArgs: [sid]);
      await InstSync.enqueueCashSale(txn, sid);
      return sid;
    });
    _changed();
    return id;
  }

  /// Customer ne saman wapas kiya: piece dobara stock mein, [refund] (0..qeemat) cash OUT; sale ka record rehta hai
  /// (wapsi ki tareekh ke saath). Qeemat − refund = kati hui raqam, dukaan ki aamdani (munafa).
  Future<void> returnSale(InstCashSale s, {required double refund, String note = '', String method = 'cash'}) async {
    await LicenseService.instance.requireWritable();
    if (!Session.isAdminOrManager) throw ArgumentError('Sirf Admin / Manager sale wapas le sakta hai.');
    if (s.isReturned) throw ArgumentError('Ye sale pehle hi wapas ho chuki hai.');
    if (!refund.isFinite || refund < 0 || refund > s.price + 0.5) {
      throw ArgumentError('Wapas di jane wali raqam 0 se ${s.price.round()} tak ho.');
    }
    if (method != 'cash' && method != 'bank') throw ArgumentError('Cash ya Bank chunein.');
    final db = await AppDatabase.instance.database;
    final now = _now();
    await db.transaction((txn) async {
      final n = await txn.update('inst_items', {'status': itemInStock, 'updatedAt': now},
          where: 'id = ? AND status = ?', whereArgs: [s.itemId, itemSold]);
      if (n > 0) await InstSync.enqueueItem(txn, s.itemId);
      int? cashId;
      if (refund > 0) {
        final cash = CashTransaction(
          type: 'OUT',
          method: method,
          amount: refund,
          reason: 'Sale wapsi: ${s.saleNo}',
          reference: 'inst-sret:${s.id}',
          createdAt: now,
          updatedAt: now,
        );
        cashId = await txn.insert('cash_transactions', cash.toMap()..remove('id'));
        await SyncQueueHelper.enqueueCashTransaction(txn, cashId);
      }
      await txn.update(
          'inst_cash_sales',
          {'returnedAt': now, 'refund': refund, 'returnNote': note.trim(), 'refundCashTxId': cashId, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [s.id]);
      await InstSync.enqueueCashSale(txn, s.id);
    });
    _changed();
  }

  /// Ghalat sale wapas: piece dobara stock mein, cash row hat'ti hai.
  Future<void> cancel(InstCashSale s) async {
    if (!Session.isAdminOrManager) throw ArgumentError('Sirf Admin / Manager sale wapas kar sakta hai.');
    final db = await AppDatabase.instance.database;
    final now = _now();
    await db.transaction((txn) async {
      final n = await txn.update('inst_items', {'status': itemInStock, 'updatedAt': now},
          where: 'id = ? AND status = ?', whereArgs: [s.itemId, itemSold]);
      if (n > 0) await InstSync.enqueueItem(txn, s.itemId);
      await _deleteCash(txn, s.id, s.cashTxId);
      if (s.isReturned) await _deleteCash(txn, s.id, s.refundCashTxId, prefix: 'inst-sret:');
      await InstSync.enqueueDeleteRow(txn, instCashSaleType, 'inst_cash_sales', 'id', s.id);
      await txn.delete('inst_cash_sales', where: 'id = ?', whereArgs: [s.id]);
    });
    _changed();
  }

  Future<void> _deleteCash(DatabaseExecutor txn, int saleId, int? cashTxId, {String prefix = 'inst-sale:'}) async {
    await SyncQueueHelper.deleteCashTransactionsByReference(txn, '$prefix$saleId');
    if (cashTxId == null) return;
    final rows = await txn.query('cash_transactions', where: 'id = ?', whereArgs: [cashTxId], limit: 1);
    if (rows.isEmpty) return;
    final row = Map<String, Object?>.from(rows.first);
    if (!(row['reference'] as String? ?? '').startsWith(prefix)) return; // kisi aur ki row nahi chhedte
    await txn.delete('cash_transactions', where: 'id = ?', whereArgs: [cashTxId]);
    await SyncQueueHelper.enqueueDelete(txn, 'cash_transaction', SyncQueueHelper.cashTransactionEntityId(row));
  }

  /// Naye pehle. [from]..[to) (null = sab).
  Future<List<CashSaleView>> list({int? from, int? to, int? customerId}) async {
    final db = await AppDatabase.instance.database;
    if ((await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_cash_sales'")).isEmpty) return const [];
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('soldAt >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('soldAt < ?');
      args.add(to);
    }
    if (customerId != null) {
      where.add('customerId = ?');
      args.add(customerId);
    }
    final rows = await db.query('inst_cash_sales',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args, orderBy: 'soldAt DESC, id DESC');
    if (rows.isEmpty) return const [];
    final sales = rows.map(InstCashSale.fromMap).toList();
    final ids = sales.map((s) => s.itemId).toSet().join(',');
    final items = <int, InstItem>{
      for (final r in await db.rawQuery('SELECT * FROM inst_items WHERE id IN ($ids)')) (r['id'] as num).toInt(): InstItem.fromMap(r)
    };
    return [for (final s in sales) CashSaleView(s, items[s.itemId])];
  }

  Future<CashSaleView?> view(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_cash_sales', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final s = InstCashSale.fromMap(rows.first);
    final it = await db.query('inst_items', where: 'id = ?', whereArgs: [s.itemId], limit: 1);
    return CashSaleView(s, it.isEmpty ? null : InstItem.fromMap(it.first));
  }

  /// Is piece ki naqd sale (item form se).
  Future<int?> saleIdForItem(int itemId) async {
    final db = await AppDatabase.instance.database;
    if ((await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='inst_cash_sales'")).isEmpty) return null;
    final r = await db.query('inst_cash_sales', columns: ['id'], where: 'itemId = ?', whereArgs: [itemId], orderBy: 'soldAt DESC', limit: 1);
    return r.isEmpty ? null : (r.first['id'] as num).toInt();
  }
}

class InstCashSale {
  final int id;
  final String saleNo;
  final int itemId;
  final int? customerId;
  final String customerName;
  final String phone;
  final double price;
  final double costPrice;
  final String method;
  final String note;
  final String soldBy;
  final int soldAt;
  final int? cashTxId;

  /// Wapsi (v44): kab, kitne wapas diye, kyun, refund ki cash row.
  final int? returnedAt;
  final double refund;
  final String returnNote;
  final int? refundCashTxId;

  const InstCashSale({
    required this.id,
    required this.saleNo,
    required this.itemId,
    this.customerId,
    this.customerName = '',
    this.phone = '',
    required this.price,
    this.costPrice = 0,
    this.method = 'cash',
    this.note = '',
    this.soldBy = '',
    required this.soldAt,
    this.cashTxId,
    this.returnedAt,
    this.refund = 0,
    this.returnNote = '',
    this.refundCashTxId,
  });

  bool get isReturned => returnedAt != null;
  bool get hasCost => costPrice > 0;

  /// Dukaan ke paas kitna raha (wapsi par qeemat − refund).
  double get kept => isReturned ? price - refund : price;

  /// Wapsi par piece stock mein wapas — munafa sirf kati hui raqam.
  double get profit => isReturned ? price - refund : (hasCost ? price - costPrice : 0);

  factory InstCashSale.fromMap(Map<String, Object?> m) => InstCashSale(
        id: ((m['id'] as num?) ?? 0).toInt(),
        saleNo: (m['saleNo'] as String?) ?? '',
        itemId: ((m['itemId'] as num?) ?? 0).toInt(),
        customerId: (m['customerId'] as num?)?.toInt(),
        customerName: (m['customerName'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        price: ((m['price'] as num?) ?? 0).toDouble(),
        costPrice: ((m['costPrice'] as num?) ?? 0).toDouble(),
        method: (m['method'] as String?) ?? 'cash',
        note: (m['note'] as String?) ?? '',
        soldBy: (m['soldBy'] as String?) ?? '',
        soldAt: ((m['soldAt'] as num?) ?? 0).toInt(),
        cashTxId: (m['cashTxId'] as num?)?.toInt(),
        returnedAt: (m['returnedAt'] as num?)?.toInt(),
        refund: ((m['refund'] as num?) ?? 0).toDouble(),
        returnNote: (m['returnNote'] as String?) ?? '',
        refundCashTxId: (m['refundCashTxId'] as num?)?.toInt(),
      );
}

class CashSaleView {
  final InstCashSale sale;
  final InstItem? item;
  const CashSaleView(this.sale, this.item);

  String get itemTitle => item == null ? '' : (item!.title.isEmpty ? item!.model : item!.title);
}

/// Customer ke liye raseed (WhatsApp / share).
String cashSaleReceipt(CashSaleView v) {
  final s = v.sale;
  final b = StringBuffer('${AppInfo.appName}\n');
  b.writeln('Cash Sale Receipt — ${s.saleNo}');
  b.writeln(DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(s.soldAt)));
  if (s.customerName.isNotEmpty) b.writeln('Customer: ${s.customerName}${s.phone.isEmpty ? '' : ' (${s.phone})'}');
  b.writeln('Item: ${v.itemTitle}');
  final it = v.item;
  if (it != null) {
    if (it.color.isNotEmpty) b.writeln('Colour: ${it.color}');
    for (final e in it.idValues.entries) {
      if (e.value.trim().isNotEmpty) b.writeln('${e.key}: ${e.value}');
    }
    if (it.warrantyMonths > 0) b.writeln('Warranty: ${it.warrantyMonths} months');
  }
  b.writeln('Price: Rs ${s.price.round()} (${s.method == 'bank' ? 'Bank' : 'Cash'}) — paid in full');
  if (s.note.isNotEmpty) b.writeln('Note: ${s.note}');
  b.writeln('Thank you!');
  return b.toString();
}
