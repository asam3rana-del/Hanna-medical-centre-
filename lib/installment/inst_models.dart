import 'dart:convert';

/// Hanna Installment — qist wale karobar ke models (Step 2: customer profile, guarantor, category, item).
///
/// Customer khud POS ki `customers` table mein hai (ledger / payments / sync wahi), us ki qist wali
/// izafi maloomat (walid ka naam, CNIC, pata...) `customer_profiles` mein 1:1. Saman (mobile, bike, LCD...)
/// `inst_items` mein — har piece ki apni row (IMEI / engine no. ke saath), kyun ke qist par har piece alag bikta hai.
/// Is file mein sab PURE hai (test/installment_models_test.dart).

// ------------------------------------------------------------------ CNIC

/// Sirf digits.
String cnicDigits(String raw) => raw.replaceAll(RegExp(r'\D'), '');

/// `3520212345671` -> `35202-1234567-1`. 13 digits na hon to jo likha wahi (trim).
String formatCnic(String raw) {
  final d = cnicDigits(raw);
  if (d.length != 13) return raw.trim();
  return '${d.substring(0, 5)}-${d.substring(5, 12)}-${d.substring(12)}';
}

/// Khali = theek (CNIC lazmi nahi). Warna poore 13 digits.
bool cnicValid(String raw) {
  final d = cnicDigits(raw);
  return d.isEmpty || d.length == 13;
}

/// Pakistani mobile number: 03xxxxxxxxx (11) ya 923xxxxxxxxx (12). Khali = theek.
bool phoneValid(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return true;
  return (d.length == 11 && d.startsWith('03')) || (d.length == 12 && d.startsWith('923'));
}

// ------------------------------------------------------------------ JSON helpers

List<String> _stringList(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    final v = jsonDecode(raw);
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is String && e.trim().isNotEmpty) e.trim()
    ];
  } catch (_) {
    return const [];
  }
}

Map<String, String> _stringMap(String raw) {
  if (raw.trim().isEmpty) return const {};
  try {
    final v = jsonDecode(raw);
    if (v is! Map) return const {};
    final out = <String, String>{};
    v.forEach((k, val) {
      if (k is String && val != null && '$val'.trim().isNotEmpty) out[k] = '$val'.trim();
    });
    return out;
  } catch (_) {
    return const {};
  }
}

/// "IMEI 1, IMEI 2" -> ['IMEI 1', 'IMEI 2'] (khali / dobara wale hata kar, tarteeb wahi).
List<String> parseIdFields(String commaText) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in commaText.split(RegExp(r'[,،\n]'))) {
    final t = part.trim();
    if (t.isEmpty) continue;
    if (seen.add(t.toLowerCase())) out.add(t);
  }
  return out;
}

/// Pehchan number ko compare karne ke liye: space / dash hata kar, chhote huroof.
String normalizeIdValue(String v) => v.replaceAll(RegExp(r'[\s\-_/]'), '').toLowerCase();

// ------------------------------------------------------------------ category

class InstCategory {
  final int? id;
  final String name;

  /// Is category ke saman ke pehchan fields, maslan Mobile: [IMEI 1, IMEI 2].
  final List<String> idFields;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  const InstCategory({
    this.id,
    required this.name,
    this.idFields = const [],
    this.sortOrder = 0,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'idFields': jsonEncode(idFields),
        'sortOrder': sortOrder,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory InstCategory.fromMap(Map<String, Object?> m) => InstCategory(
        id: (m['id'] as num?)?.toInt(),
        name: (m['name'] as String?) ?? '',
        idFields: _stringList((m['idFields'] as String?) ?? ''),
        sortOrder: ((m['sortOrder'] as num?) ?? 0).toInt(),
        createdAt: ((m['createdAt'] as num?) ?? 0).toInt(),
        updatedAt: ((m['updatedAt'] as num?) ?? 0).toInt(),
      );

  InstCategory copyWith({String? name, List<String>? idFields, int? sortOrder, int? updatedAt}) => InstCategory(
        id: id,
        name: name ?? this.name,
        idFields: idFields ?? this.idFields,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Pehli baar app khulne par yeh categories khud ban jati hain (baad mein badli / mitai ja sakti hain).
const defaultInstCategories = <(String, List<String>)>[
  ('Mobile', ['IMEI 1', 'IMEI 2']),
  ('Motorcycle', ['Engine No.', 'Chassis No.', 'Registration No.']),
  ('LED / TV', ['Serial No.']),
  ('Refrigerator', ['Serial No.']),
  ('Air Conditioner', ['Serial No.']),
  ('Washing Machine', ['Serial No.']),
  ('Laptop', ['Serial No.']),
  ('Furniture', []),
  ('Other', ['Serial No.']),
];

// ------------------------------------------------------------------ item

const itemInStock = 'in_stock';
const itemSold = 'sold';
const itemReturned = 'returned';
const itemRepossessed = 'repossessed';

const itemStatuses = <String>[itemInStock, itemSold, itemReturned, itemRepossessed];

/// Ek piece (ek mobile / ek bike). Qist par bikne ke baad `status = sold` (Step 3 mein plan se judega).
class InstItem {
  final int? id;
  final int categoryId;

  /// Company (Samsung, Honda, Haier...).
  final String brand;

  /// Model (A15 128GB, CD-70 2026, 32" LED...).
  final String model;
  final String color;

  /// Pehchan numbers: category ke field ka naam -> value. Maslan {'IMEI 1': '35...'}.
  final Map<String, String> idValues;

  /// Khareed qeemat (profit ke liye; cashier ko nahi dikhti).
  final double costPrice;

  /// Naqd (cash) qeemat — qist plan isi se shuru hota hai.
  final double cashPrice;
  final int warrantyMonths;
  final String supplier;
  final String note;
  final String status;

  /// Kab khareeda (din ki shuruaat, millis). 0 = nahi likha.
  final int purchaseDate;
  final int createdAt;
  final int updatedAt;

  const InstItem({
    this.id,
    required this.categoryId,
    this.brand = '',
    required this.model,
    this.color = '',
    this.idValues = const {},
    this.costPrice = 0,
    this.cashPrice = 0,
    this.warrantyMonths = 0,
    this.supplier = '',
    this.note = '',
    this.status = itemInStock,
    this.purchaseDate = 0,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  String get title => [brand, model].where((s) => s.trim().isNotEmpty).join(' ');

  bool get inStock => status == itemInStock;

  /// Pehla bhara hua pehchan number (list mein dikhane ke liye), maslan "IMEI 1: 35...".
  String get primaryId {
    for (final e in idValues.entries) {
      if (e.value.trim().isNotEmpty) return '${e.key}: ${e.value}';
    }
    return '';
  }

  /// Search: brand / model / color / koi bhi pehchan number (space / dash ke baghair bhi milta hai).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = '$brand $model $color $supplier'.toLowerCase();
    if (q.split(RegExp(r'\s+')).every(hay.contains)) return true;
    final nq = normalizeIdValue(q);
    if (nq.isEmpty) return false;
    return idValues.values.any((v) => normalizeIdValue(v).contains(nq));
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'categoryId': categoryId,
        'brand': brand,
        'model': model,
        'color': color,
        'idValues': jsonEncode(idValues),
        'costPrice': costPrice,
        'cashPrice': cashPrice,
        'warrantyMonths': warrantyMonths,
        'supplier': supplier,
        'note': note,
        'status': status,
        'purchaseDate': purchaseDate,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory InstItem.fromMap(Map<String, Object?> m) => InstItem(
        id: (m['id'] as num?)?.toInt(),
        categoryId: ((m['categoryId'] as num?) ?? 0).toInt(),
        brand: (m['brand'] as String?) ?? '',
        model: (m['model'] as String?) ?? '',
        color: (m['color'] as String?) ?? '',
        idValues: _stringMap((m['idValues'] as String?) ?? ''),
        costPrice: ((m['costPrice'] as num?) ?? 0).toDouble(),
        cashPrice: ((m['cashPrice'] as num?) ?? 0).toDouble(),
        warrantyMonths: ((m['warrantyMonths'] as num?) ?? 0).toInt(),
        supplier: (m['supplier'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        status: (m['status'] as String?) ?? itemInStock,
        purchaseDate: ((m['purchaseDate'] as num?) ?? 0).toInt(),
        createdAt: ((m['createdAt'] as num?) ?? 0).toInt(),
        updatedAt: ((m['updatedAt'] as num?) ?? 0).toInt(),
      );

  InstItem copyWith({
    int? categoryId,
    String? brand,
    String? model,
    String? color,
    Map<String, String>? idValues,
    double? costPrice,
    double? cashPrice,
    int? warrantyMonths,
    String? supplier,
    String? note,
    String? status,
    int? purchaseDate,
    int? updatedAt,
  }) =>
      InstItem(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        brand: brand ?? this.brand,
        model: model ?? this.model,
        color: color ?? this.color,
        idValues: idValues ?? this.idValues,
        costPrice: costPrice ?? this.costPrice,
        cashPrice: cashPrice ?? this.cashPrice,
        warrantyMonths: warrantyMonths ?? this.warrantyMonths,
        supplier: supplier ?? this.supplier,
        note: note ?? this.note,
        status: status ?? this.status,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// [candidate] ka koi pehchan number [others] mein kisi aur piece ka to nahi? Mila to "IMEI 1: 35..." wapas.
/// Mobile ka IMEI 1 aur doosre ka IMEI 2 bhi aapas mein compare hote hain (field ka naam nahi dekha jata).
String? findDuplicateId(InstItem candidate, Iterable<InstItem> others) {
  for (final mine in candidate.idValues.entries) {
    final a = normalizeIdValue(mine.value);
    if (a.length < 4) continue; // bohat chhota number (maslan "1") par shor na ho
    for (final o in others) {
      if (o.id != null && o.id == candidate.id) continue;
      for (final v in o.idValues.values) {
        if (normalizeIdValue(v) == a) return '${mine.key}: ${mine.value}';
      }
    }
  }
  return null;
}

// ------------------------------------------------------------------ customer profile

/// `customers` row ki qist wali izafi maloomat (1:1, PK = customerId).
class CustomerProfile {
  final int customerId;
  final String fatherName;
  final String cnic;
  final String phone2;
  final String address;

  /// Kaam / naukri / karobar.
  final String occupation;
  final String workAddress;

  /// Mahana aamdani (andaza) — qist kitni ho sakti hai, faisla karne mein madad.
  final double monthlyIncome;
  final String note;
  final int createdAt;
  final int updatedAt;

  /// Dukaan ke purane register ka khata number (v47) — search mein bhi.
  final String khataNo;

  /// Blacklist (v45): khali nahi = customer block (wajah). Sirf [InstRepository.setBlocked] likhta hai —
  /// [toMap] mein nahi, taake profile edit karne se block na hatay.
  final String blockedReason;
  final int blockedAt;
  bool get isBlocked => blockedReason.trim().isNotEmpty;

  const CustomerProfile({
    required this.customerId,
    this.fatherName = '',
    this.cnic = '',
    this.phone2 = '',
    this.address = '',
    this.occupation = '',
    this.workAddress = '',
    this.monthlyIncome = 0,
    this.note = '',
    this.createdAt = 0,
    this.updatedAt = 0,
    this.khataNo = '',
    this.blockedReason = '',
    this.blockedAt = 0,
  });

  Map<String, Object?> toMap() => {
        'customerId': customerId,
        'fatherName': fatherName,
        'cnic': cnic,
        'phone2': phone2,
        'address': address,
        'occupation': occupation,
        'workAddress': workAddress,
        'monthlyIncome': monthlyIncome,
        'note': note,
        'khataNo': khataNo.trim(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory CustomerProfile.fromMap(Map<String, Object?> m) => CustomerProfile(
        customerId: ((m['customerId'] as num?) ?? 0).toInt(),
        fatherName: (m['fatherName'] as String?) ?? '',
        cnic: (m['cnic'] as String?) ?? '',
        phone2: (m['phone2'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        occupation: (m['occupation'] as String?) ?? '',
        workAddress: (m['workAddress'] as String?) ?? '',
        monthlyIncome: ((m['monthlyIncome'] as num?) ?? 0).toDouble(),
        note: (m['note'] as String?) ?? '',
        createdAt: ((m['createdAt'] as num?) ?? 0).toInt(),
        updatedAt: ((m['updatedAt'] as num?) ?? 0).toInt(),
        khataNo: (m['khataNo'] as String?) ?? '',
        blockedReason: (m['blockedReason'] as String?) ?? '',
        blockedAt: ((m['blockedAt'] as num?) ?? 0).toInt(),
      );
}

/// List screen ke liye: customer + profile + kitne guarantor.
class InstCustomerRow {
  final int id;
  final String name;
  final String phone;
  final CustomerProfile? profile;
  final int guarantorCount;
  const InstCustomerRow({
    required this.id,
    required this.name,
    required this.phone,
    this.profile,
    this.guarantorCount = 0,
  });

  /// Naam / walid / phone / CNIC (dash ke baghair bhi) / pata.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final p = profile;
    final hay = '$name ${p?.fatherName ?? ''} ${p?.address ?? ''} ${p?.khataNo ?? ''}'.toLowerCase();
    if (q.split(RegExp(r'\s+')).every(hay.contains)) return true;
    final k = (p?.khataNo ?? '').trim().toLowerCase();
    if (k.isNotEmpty && k == q) return true;
    final dq = q.replaceAll(RegExp(r'\D'), '');
    if (dq.length < 3) return false;
    final digits = '${phone.replaceAll(RegExp(r'\D'), '')} '
        '${(p?.phone2 ?? '').replaceAll(RegExp(r'\D'), '')} ${cnicDigits(p?.cnic ?? '')}';
    return digits.contains(dq);
  }
}

// ------------------------------------------------------------------ guarantor

class Guarantor {
  final int? id;
  final int customerId;
  final String name;
  final String fatherName;
  final String cnic;
  final String phone;
  final String address;

  /// Customer se rishta (bhai, dost, padosi...).
  final String relation;
  final String occupation;
  final int createdAt;
  final int updatedAt;

  const Guarantor({
    this.id,
    required this.customerId,
    required this.name,
    this.fatherName = '',
    this.cnic = '',
    this.phone = '',
    this.address = '',
    this.relation = '',
    this.occupation = '',
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'customerId': customerId,
        'name': name,
        'fatherName': fatherName,
        'cnic': cnic,
        'phone': phone,
        'address': address,
        'relation': relation,
        'occupation': occupation,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory Guarantor.fromMap(Map<String, Object?> m) => Guarantor(
        id: (m['id'] as num?)?.toInt(),
        customerId: ((m['customerId'] as num?) ?? 0).toInt(),
        name: (m['name'] as String?) ?? '',
        fatherName: (m['fatherName'] as String?) ?? '',
        cnic: (m['cnic'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        relation: (m['relation'] as String?) ?? '',
        occupation: (m['occupation'] as String?) ?? '',
        createdAt: ((m['createdAt'] as num?) ?? 0).toInt(),
        updatedAt: ((m['updatedAt'] as num?) ?? 0).toInt(),
      );
}
