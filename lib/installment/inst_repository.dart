import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:sqflite/sqflite.dart' show Sqflite;

import '../db/app_database.dart';
import '../license/license_service.dart';
import '../services/session.dart';
import '../db/party_repository.dart';
import '../models/party.dart';
import 'inst_models.dart';
import 'inst_plan_math.dart' show parseIdList;
import 'inst_reports.dart';
import 'inst_sync.dart';

/// Hanna Installment ka data: customer profile (CNIC...), guarantor, category, item.
///
/// Customer ki asal row POS wali `customers` table mein [PartyRepository.saveCustomer] se banti hai — is tarah
/// customer ka ledger / payment / statement / sync sab pehle jaisa chalta hai. Yahan sirf izafi maloomat.
class InstRepository {
  InstRepository._() {
    // Doosre device se qist data aane par screens refresh.
    InstSync.onApplied = () => changes.value++;
  }
  static final InstRepository instance = InstRepository._();

  /// Kuch bhi badle to barhta hai — screens sun kar dobara load karti hain.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  int _now() => DateTime.now().millisecondsSinceEpoch;
  void _changed() => changes.value++;

  // ================================================================ customers

  /// Saare customers (POS wale bhi) + un ki profile + guarantor count. Naam ke hisaab se.
  Future<List<InstCustomerRow>> listCustomers() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.id AS id, c.name AS name, c.phone AS phone,
             p.customerId AS pCustomerId, p.fatherName, p.cnic, p.phone2, p.address, p.occupation,
             p.workAddress, p.monthlyIncome, p.note, p.createdAt, p.updatedAt, p.khataNo, p.blockedReason, p.blockedAt,
             (SELECT COUNT(*) FROM inst_guarantors g WHERE g.customerId = c.id) AS gCount
      FROM customers c
      LEFT JOIN customer_profiles p ON p.customerId = c.id
      WHERE c.kind = '' OR c.kind IS NULL
      ORDER BY c.name COLLATE NOCASE ASC
    ''');
    return [
      for (final r in rows)
        InstCustomerRow(
          id: (r['id'] as num).toInt(),
          name: (r['name'] as String?) ?? '',
          phone: (r['phone'] as String?) ?? '',
          profile: r['pCustomerId'] == null ? null : CustomerProfile.fromMap({...r, 'customerId': r['pCustomerId']}),
          guarantorCount: ((r['gCount'] as num?) ?? 0).toInt(),
        )
    ];
  }

  Future<Customer?> customer(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<CustomerProfile?> profile(int customerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('customer_profiles', where: 'customerId = ?', whereArgs: [customerId], limit: 1);
    return rows.isEmpty ? null : CustomerProfile.fromMap(rows.first);
  }

  /// Is CNIC wala koi aur customer? Mila to us ka naam. Khali CNIC => null.
  Future<String?> customerWithCnic(String cnic, {int? exceptCustomerId}) async {
    final d = cnicDigits(cnic);
    if (d.length != 13) return null;
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.name AS name, p.cnic AS cnic FROM customer_profiles p
      JOIN customers c ON c.id = p.customerId
      WHERE p.customerId != ? AND p.cnic != ''
    ''', [exceptCustomerId ?? -1]);
    for (final r in rows) {
      if (cnicDigits((r['cnic'] as String?) ?? '') == d) return (r['name'] as String?) ?? '';
    }
    return null;
  }

  /// Naya customer (POS `customers` row + profile). [ArgumentError] = galat input (message dikhayein).
  Future<int> addCustomer({required String name, required String phone, required CustomerProfile profile}) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Customer ka naam likhein.');
    _validateProfile(phone, profile);
    final dup = await customerWithCnic(profile.cnic);
    if (dup != null) throw ArgumentError('Ye CNIC pehle se "$dup" ke naam par darj hai.');
    final id = await PartyRepository.instance.saveCustomer(Customer(name: n, phone: phone.trim()));
    await _writeProfile(id, profile, isNew: true);
    _changed();
    return id;
  }

  Future<void> updateCustomer(Customer existing, {required String name, required String phone, required CustomerProfile profile}) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Customer ka naam likhein.');
    if (existing.id == null) throw ArgumentError('Customer nahi mila.');
    _validateProfile(phone, profile);
    final dup = await customerWithCnic(profile.cnic, exceptCustomerId: existing.id);
    if (dup != null) throw ArgumentError('Ye CNIC pehle se "$dup" ke naam par darj hai.');
    if (n != existing.name || phone.trim() != existing.phone) {
      await PartyRepository.instance.updateCustomer(existing.copyWith(name: n, phone: phone.trim()));
    }
    await _writeProfile(existing.id!, profile, isNew: false);
    _changed();
  }

  void _validateProfile(String phone, CustomerProfile p) {
    if (!phoneValid(phone)) throw ArgumentError('Phone number theek nahi (03xx xxxxxxx).');
    if (!phoneValid(p.phone2)) throw ArgumentError('Doosra phone number theek nahi (03xx xxxxxxx).');
    if (!cnicValid(p.cnic)) throw ArgumentError('CNIC ke poore 13 hindse likhein.');
  }

  Future<void> _writeProfile(int customerId, CustomerProfile p, {required bool isNew}) async {
    final db = await AppDatabase.instance.database;
    final now = _now();
    final old = isNew ? null : await profile(customerId);
    final row = CustomerProfile(
      customerId: customerId,
      fatherName: p.fatherName.trim(),
      cnic: p.cnic.trim().isEmpty ? '' : formatCnic(p.cnic),
      phone2: p.phone2.trim(),
      address: p.address.trim(),
      occupation: p.occupation.trim(),
      workAddress: p.workAddress.trim(),
      monthlyIncome: p.monthlyIncome < 0 ? 0 : p.monthlyIncome,
      note: p.note.trim(),
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    ).toMap();
    await db.transaction((txn) async {
      if (old == null) {
        await txn.insert('customer_profiles', row);
      } else {
        await txn.update('customer_profiles', row, where: 'customerId = ?', whereArgs: [customerId]);
      }
      await InstSync.enqueueProfile(txn, customerId);
    });
  }

  /// Blacklist (Step 18, admin / manager). [reason] khali = block hatao. Profile na ho to ban jati hai.
  Future<void> setBlocked(int customerId, String reason) async {
    await LicenseService.instance.requireWritable();
    if (!Session.isAdminOrManager) throw ArgumentError('Sirf Admin / Manager customer block kar sakta hai.');
    final r = reason.trim();
    final db = await AppDatabase.instance.database;
    final now = _now();
    await db.transaction((txn) async {
      final values = {'blockedReason': r, 'blockedAt': r.isEmpty ? 0 : now, 'updatedAt': now};
      final n = await txn.update('customer_profiles', values, where: 'customerId = ?', whereArgs: [customerId]);
      if (n == 0) await txn.insert('customer_profiles', {...values, 'customerId': customerId, 'createdAt': now});
      await InstSync.enqueueProfile(txn, customerId);
    });
    _changed();
  }

  /// Naya plan / naqd sale se pehle: block ki wajah aur kitni dafa saman wapas liya gaya. Sab theek => null.
  Future<CustomerRisk?> risk(int customerId) async {
    final db = await AppDatabase.instance.database;
    final p = await profile(customerId);
    final repo = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM inst_plans WHERE customerId = ? AND status = 'repossessed'", [customerId])) ??
        0;
    final r = CustomerRisk(blockedReason: p?.blockedReason.trim() ?? '', repossessed: repo);
    return r.any ? r : null;
  }

  /// Zamin ki jaanch (Step 23): chune gaye zamin ka CNIC kisi blacklist / saman-wapas customer ka to nahi, ya woh
  /// pehle kisi aise plan ka zamin to nahi jis ka saman wapas liya gaya. Wapas: har masle ki ek line.
  Future<List<String>> guarantorRisks(List<int> guarantorIds) async {
    if (guarantorIds.isEmpty) return const [];
    final db = await AppDatabase.instance.database;
    final picked = [
      for (final r in await db.query('inst_guarantors', where: 'id IN (${guarantorIds.map((_) => '?').join(',')})', whereArgs: guarantorIds))
        Guarantor.fromMap(r)
    ];
    final profiles = await db.rawQuery('''
      SELECT p.customerId AS cid, p.cnic AS cnic, p.blockedReason AS reason, c.name AS name,
        (SELECT COUNT(*) FROM inst_plans x WHERE x.customerId = p.customerId AND x.status = 'repossessed') AS rep
      FROM customer_profiles p JOIN customers c ON c.id = p.customerId WHERE p.cnic != ''
    ''');
    final allG = await db.query('inst_guarantors', columns: ['id', 'cnic']);
    final repoPlans = await db.query('inst_plans', columns: ['guarantorIds', 'planNo'], where: "status = 'repossessed'");
    final out = <String>[];
    for (final g in picked) {
      final d = cnicDigits(g.cnic);
      if (d.length != 13) continue;
      for (final r in profiles) {
        if (cnicDigits((r['cnic'] as String?) ?? '') != d) continue;
        final reason = ((r['reason'] as String?) ?? '').trim();
        final rep = ((r['rep'] as num?) ?? 0).toInt();
        if (reason.isNotEmpty) out.add('${g.name}: blacklist customer "${r['name']}" ($reason)');
        if (rep > 0) out.add('${g.name}: customer "${r['name']}" se $rep dafa saman wapas liya gaya');
      }
      final sameIds = {
        for (final x in allG)
          if (cnicDigits((x['cnic'] as String?) ?? '') == d) ((x['id'] as num?) ?? 0).toInt()
      };
      final bad = <String>[];
      for (final pl in repoPlans) {
        if (parseIdList((pl['guarantorIds'] as String?) ?? '').any(sameIds.contains)) bad.add((pl['planNo'] as String?) ?? '');
      }
      if (bad.isNotEmpty) out.add('${g.name}: pehle zamin tha, saman wapas liya gaya (${bad.join(', ')})');
    }
    return out;
  }

  // ================================================================ guarantors

  Future<List<Guarantor>> guarantors(int customerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_guarantors', where: 'customerId = ?', whereArgs: [customerId], orderBy: 'id ASC');
    return rows.map(Guarantor.fromMap).toList();
  }

  /// Naya / purana guarantor save. Wapas: id.
  Future<int> saveGuarantor(Guarantor g) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    if (g.name.trim().isEmpty) throw ArgumentError('Guarantor ka naam likhein.');
    if (!phoneValid(g.phone)) throw ArgumentError('Guarantor ka phone number theek nahi (03xx xxxxxxx).');
    if (!cnicValid(g.cnic)) throw ArgumentError('Guarantor ki CNIC ke poore 13 hindse likhein.');
    final db = await AppDatabase.instance.database;
    // Customer khud apna zamin nahi ho sakta.
    final own = await profile(g.customerId);
    if (own != null && cnicDigits(g.cnic).length == 13 && cnicDigits(own.cnic) == cnicDigits(g.cnic)) {
      throw ArgumentError('Guarantor ki CNIC customer ki apni CNIC hai — koi aur banda chunein.');
    }
    final now = _now();
    final row = Guarantor(
      id: g.id,
      customerId: g.customerId,
      name: g.name.trim(),
      fatherName: g.fatherName.trim(),
      cnic: g.cnic.trim().isEmpty ? '' : formatCnic(g.cnic),
      phone: g.phone.trim(),
      address: g.address.trim(),
      relation: g.relation.trim(),
      occupation: g.occupation.trim(),
      createdAt: g.createdAt == 0 ? now : g.createdAt,
      updatedAt: now,
    ).toMap();
    final id = await db.transaction((txn) async {
      int id;
      if (g.id == null) {
        id = await txn.insert('inst_guarantors', row..remove('id'));
      } else {
        await txn.update('inst_guarantors', row, where: 'id = ?', whereArgs: [g.id]);
        id = g.id!;
      }
      await InstSync.enqueueGuarantor(txn, id);
      return id;
    });
    _changed();
    return id;
  }

  Future<void> deleteGuarantor(int id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instGuarantorType, 'inst_guarantors', 'id', id);
      await txn.delete('inst_guarantors', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  /// Ye CNIC kitne customers ka zamin hai (ek banda bohat logon ka zamin ho to khatra). Customer naam wapas.
  Future<List<String>> guaranteesByCnic(String cnic, {int? exceptGuarantorId}) async {
    final d = cnicDigits(cnic);
    if (d.length != 13) return const [];
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT g.id AS id, g.cnic AS cnic, c.name AS name FROM inst_guarantors g
      JOIN customers c ON c.id = g.customerId WHERE g.cnic != ''
    ''');
    return [
      for (final r in rows)
        if ((r['id'] as num).toInt() != (exceptGuarantorId ?? -1) && cnicDigits((r['cnic'] as String?) ?? '') == d)
          (r['name'] as String?) ?? ''
    ];
  }

  // ================================================================ categories

  Future<List<InstCategory>> categories() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_categories', orderBy: 'sortOrder ASC, name COLLATE NOCASE ASC');
    return rows.map(InstCategory.fromMap).toList();
  }

  Future<int> saveCategory(InstCategory c) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    final name = c.name.trim();
    if (name.isEmpty) throw ArgumentError('Category ka naam likhein.');
    final db = await AppDatabase.instance.database;
    final clash = await db.rawQuery(
        'SELECT id FROM inst_categories WHERE LOWER(TRIM(name)) = ? AND id != ? LIMIT 1', [name.toLowerCase(), c.id ?? -1]);
    if (clash.isNotEmpty) throw ArgumentError('"$name" naam ki category pehle se hai.');
    final now = _now();
    final id = await db.transaction((txn) async {
      int id;
      if (c.id == null) {
        final maxOrder = Sqflite.firstIntValue(await txn.rawQuery('SELECT COALESCE(MAX(sortOrder), 0) FROM inst_categories')) ?? 0;
        id = await txn.insert(
            'inst_categories',
            InstCategory(name: name, idFields: c.idFields, sortOrder: maxOrder + 1, createdAt: now, updatedAt: now).toMap()
              ..remove('id'));
      } else {
        await txn.update('inst_categories', c.copyWith(name: name, updatedAt: now).toMap(), where: 'id = ?', whereArgs: [c.id]);
        id = c.id!;
      }
      await InstSync.enqueueCategory(txn, id);
      return id;
    });
    _changed();
    return id;
  }

  /// Is category mein saman ho to delete nahi (pehle saman doosri category mein karein).
  Future<void> deleteCategory(int id) async {
    final db = await AppDatabase.instance.database;
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inst_items WHERE categoryId = ?', [id])) ?? 0;
    if (n > 0) throw ArgumentError('Is category mein $n saman hai — pehle us ko hatayein ya category badlein.');
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instCategoryType, 'inst_categories', 'id', id);
      await txn.delete('inst_categories', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  // ================================================================ items

  Future<List<InstItem>> items({int? categoryId, String? status}) async {
    final db = await AppDatabase.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (categoryId != null) {
      where.add('categoryId = ?');
      args.add(categoryId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    final rows = await db.query('inst_items',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args, orderBy: 'createdAt DESC');
    return rows.map(InstItem.fromMap).toList();
  }

  /// Naya / purana piece save. Ek hi IMEI / serial do pieces par nahi (duplicate => [ArgumentError]).
  Future<int> saveItem(InstItem item) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    if (item.model.trim().isEmpty) throw ArgumentError('Model / naam likhein.');
    if (item.cashPrice < 0 || item.costPrice < 0) throw ArgumentError('Qeemat minus nahi ho sakti.');
    final db = await AppDatabase.instance.database;
    final cat = await db.query('inst_categories', where: 'id = ?', whereArgs: [item.categoryId], limit: 1);
    if (cat.isEmpty) throw ArgumentError('Category chunein.');
    final dup = findDuplicateId(item, await items());
    if (dup != null) throw ArgumentError('$dup pehle se kisi aur piece par darj hai.');
    final now = _now();
    final clean = item.copyWith(
      brand: item.brand.trim(),
      model: item.model.trim(),
      color: item.color.trim(),
      supplier: item.supplier.trim(),
      note: item.note.trim(),
      idValues: {
        for (final e in item.idValues.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim()
      },
      updatedAt: now,
    );
    final id = await db.transaction((txn) async {
      int id;
      if (item.id == null) {
        id = await txn.insert('inst_items', clean.toMap()..remove('id')..['createdAt'] = now);
      } else {
        final before = await txn.query('inst_items', where: 'id = ?', whereArgs: [item.id], limit: 1);
        await txn.update('inst_items', clean.toMap(), where: 'id = ?', whereArgs: [item.id]);
        id = item.id!;
        // Form se qeemat badli: rate history mein bhi (Rate Badlein screen jaisa).
        if (before.isNotEmpty) {
          final old = InstItem.fromMap(before.first);
          if ((old.cashPrice - clean.cashPrice).abs() >= 0.005 || (old.costPrice - clean.costPrice).abs() >= 0.005) {
            final hid = await txn.insert('inst_price_changes', {
              'itemId': id,
              'oldCash': old.cashPrice,
              'newCash': clean.cashPrice,
              'oldCost': old.costPrice,
              'newCost': clean.costPrice,
              'note': 'Edit',
              'changedBy': Session.username ?? '',
              'changedAt': now,
            });
            await InstSync.enqueuePriceChange(txn, hid);
          }
        }
      }
      await InstSync.enqueueItem(txn, id);
      return id;
    });
    _changed();
    return id;
  }

  /// Sirf stock wala piece delete (bika hua piece qist ke record ka hissa hai).
  Future<void> deleteItem(InstItem item) async {
    if (item.id == null) return;
    if (!item.inStock) throw ArgumentError('Ye piece stock mein nahi (bik chuka / wapas) — delete nahi ho sakta.');
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await InstSync.enqueueDeleteRow(txn, instItemType, 'inst_items', 'id', item.id!);
      await txn.delete('inst_items', where: 'id = ?', whereArgs: [item.id]);
    });
    _changed();
  }

  // ================================================================ rate badalna (Step 9)

  /// Stock ke pieces ka naya rate. [newCash] / [newCost]: itemId -> nayi qeemat (null = woh na badlo).
  /// Sirf stock (in_stock) wale pieces; har tabdeeli ka record `inst_price_changes` mein. Wapas: kitne pieces badle.
  /// Pehle se bane qist plan NAHI badalte (un ki qeemat plan mein mehfooz hai).
  Future<int> changeRates({required Map<int, double> newCash, Map<int, double> newCost = const {}, String note = ''}) async {
    await LicenseService.instance.requireWritable(); // license khatam / tareekh ghalat => sirf dekhna
    if (!Session.isAdminOrManager) throw ArgumentError('Sirf Admin / Manager rate badal sakta hai.');
    final ids = {...newCash.keys, ...newCost.keys};
    if (ids.isEmpty) throw ArgumentError('Koi piece nahi chuna.');
    for (final v in [...newCash.values, ...newCost.values]) {
      if (!v.isFinite || v < 0) throw ArgumentError('Rate minus nahi ho sakta.');
    }
    final db = await AppDatabase.instance.database;
    final now = _now();
    var changed = 0;
    await db.transaction((txn) async {
      for (final id in ids) {
        final rows = await txn.query('inst_items', where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) continue;
        final it = InstItem.fromMap(rows.first);
        if (!it.inStock) continue;
        final cash = newCash[id] ?? it.cashPrice;
        final cost = newCost[id] ?? it.costPrice;
        if ((cash - it.cashPrice).abs() < 0.005 && (cost - it.costPrice).abs() < 0.005) continue;
        await txn.update('inst_items', {'cashPrice': cash, 'costPrice': cost, 'updatedAt': now}, where: 'id = ?', whereArgs: [id]);
        final hid = await txn.insert('inst_price_changes', {
          'itemId': id,
          'oldCash': it.cashPrice,
          'newCash': cash,
          'oldCost': it.costPrice,
          'newCost': cost,
          'note': note.trim(),
          'changedBy': Session.username ?? '',
          'changedAt': now,
        });
        await InstSync.enqueueItem(txn, id);
        await InstSync.enqueuePriceChange(txn, hid);
        changed++;
      }
    });
    _changed();
    return changed;
  }

  /// Ek piece ki rate history (naye pehle).
  Future<List<PriceChange>> priceHistory(int itemId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('inst_price_changes', where: 'itemId = ?', whereArgs: [itemId], orderBy: 'changedAt DESC, id DESC');
    return rows.map(PriceChange.fromMap).toList();
  }

  /// Muddat ki rate tabdeeliyan (report): (kitni, naqd maliyat ka farq, khareed maliyat ka farq).
  Future<(int, double, double)> priceChangeSummary({required int from, required int to}) async {
    final db = await AppDatabase.instance.database;
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS n, COALESCE(SUM(newCash - oldCash), 0) AS cash, COALESCE(SUM(newCost - oldCost), 0) AS cost '
        'FROM inst_price_changes WHERE changedAt >= ? AND changedAt < ?',
        [from, to]);
    final m = r.first;
    return (((m['n'] as num?) ?? 0).toInt(), ((m['cash'] as num?) ?? 0).toDouble(), ((m['cost'] as num?) ?? 0).toDouble());
  }

  /// Stock ki maliyat (sirf in_stock pieces).
  Future<StockValue> stockValue() async {
    final db = await AppDatabase.instance.database;
    final r = await db.rawQuery(
        "SELECT COUNT(*) AS n, COALESCE(SUM(costPrice), 0) AS cost, COALESCE(SUM(cashPrice), 0) AS cash FROM inst_items WHERE status = 'in_stock'");
    final m = r.first;
    return StockValue(((m['n'] as num?) ?? 0).toInt(), ((m['cost'] as num?) ?? 0).toDouble(), ((m['cash'] as num?) ?? 0).toDouble());
  }

  /// App ke `cash_transactions` ke hisaab se haath mein (cash) aur bank: sab IN − sab OUT (shuru ka cash Cash screen se "Cash In").
  Future<(double, double)> cashBalances() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
        "SELECT method, COALESCE(SUM(CASE WHEN type = 'IN' THEN amount WHEN type = 'OUT' THEN -amount ELSE 0 END), 0) AS v "
        'FROM cash_transactions GROUP BY method');
    var cash = 0.0, bank = 0.0;
    for (final r in rows) {
      final v = ((r['v'] as num?) ?? 0).toDouble();
      if ((r['method'] as String?) == 'bank') {
        bank += v;
      } else {
        cash += v;
      }
    }
    return (cash, bank);
  }

  // ================================================================ home stats

  Future<InstHomeStats> homeStats() async {
    final db = await AppDatabase.instance.database;
    int count(List<Map<String, Object?>> r) => ((r.first.values.first as num?) ?? 0).toInt();
    double sum(List<Map<String, Object?>> r) => ((r.first.values.first as num?) ?? 0).toDouble();
    final customers = count(await db.rawQuery("SELECT COUNT(*) FROM customers WHERE kind = '' OR kind IS NULL"));
    final inStock = count(await db.rawQuery("SELECT COUNT(*) FROM inst_items WHERE status = 'in_stock'"));
    final stockValue = sum(await db.rawQuery("SELECT COALESCE(SUM(costPrice), 0) FROM inst_items WHERE status = 'in_stock'"));
    final noGuarantor = count(await db.rawQuery('''
      SELECT COUNT(*) FROM customer_profiles p
      WHERE NOT EXISTS (SELECT 1 FROM inst_guarantors g WHERE g.customerId = p.customerId)
    '''));
    return InstHomeStats(customers: customers, itemsInStock: inStock, stockCostValue: stockValue, profilesWithoutGuarantor: noGuarantor);
  }
}

class InstHomeStats {
  final int customers;
  final int itemsInStock;
  final double stockCostValue;
  final int profilesWithoutGuarantor;
  const InstHomeStats({
    this.customers = 0,
    this.itemsInStock = 0,
    this.stockCostValue = 0,
    this.profilesWithoutGuarantor = 0,
  });
}

/// Rate tabdeeli ka ek record.
class PriceChange {
  final int id;
  final int itemId;
  final double oldCash;
  final double newCash;
  final double oldCost;
  final double newCost;
  final String note;
  final String changedBy;
  final int changedAt;
  const PriceChange({
    required this.id,
    required this.itemId,
    required this.oldCash,
    required this.newCash,
    required this.oldCost,
    required this.newCost,
    required this.note,
    required this.changedBy,
    required this.changedAt,
  });

  bool get costChanged => (newCost - oldCost).abs() >= 0.005;

  factory PriceChange.fromMap(Map<String, Object?> m) {
    double d(String k) => ((m[k] as num?) ?? 0).toDouble();
    return PriceChange(
      id: ((m['id'] as num?) ?? 0).toInt(),
      itemId: ((m['itemId'] as num?) ?? 0).toInt(),
      oldCash: d('oldCash'),
      newCash: d('newCash'),
      oldCost: d('oldCost'),
      newCost: d('newCost'),
      note: (m['note'] as String?) ?? '',
      changedBy: (m['changedBy'] as String?) ?? '',
      changedAt: ((m['changedAt'] as num?) ?? 0).toInt(),
    );
  }
}


/// Customer ka khatra (Step 18): block ki wajah / pehle saman wapas.
class CustomerRisk {
  final String blockedReason;
  final int repossessed;
  const CustomerRisk({required this.blockedReason, required this.repossessed});
  bool get blocked => blockedReason.isNotEmpty;
  bool get any => blocked || repossessed > 0;
}
