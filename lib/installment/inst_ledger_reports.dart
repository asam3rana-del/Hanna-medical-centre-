import 'inst_cash_sale_repository.dart';
import 'inst_models.dart';
import 'inst_plan_math.dart';
import 'inst_plan_repository.dart';

/// Reports hub ke hisaab (PURE — DB nahi; test/installment_ledger_reports_test.dart).
///   * Sale report: muddat mein bane plan (kis ko, kya, kitne ka, mutawaqqa munafa)
///   * Stock report: category wise + kitne din se para hai
///   * Qist report: muddat mein aane wali na-adaa qisten (late bhi)
///   * Lena (receivable): customer wise baqi / late
///   * Karobar ki surat: lena + stock − dena

int _daysBetween(int fromMs, int toMs) {
  final a = DateTime.fromMillisecondsSinceEpoch(fromMs);
  final b = DateTime.fromMillisecondsSinceEpoch(toMs);
  return DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;
}

double _r(double v) => (v * 100).roundToDouble() / 100;

// ==================================================================== sale

class SaleRow {
  final int planId;
  final String planNo;
  final int date;
  final String customer;
  final String item;
  final String itemId;
  final int? categoryId;
  final double cashPrice;
  final double advance;
  final double totalPrice;
  final double costPrice;
  final String status;

  /// Naqd sale ho to us ki id ([planId] tab 0).
  final int? cashSaleId;
  const SaleRow({
    required this.planId,
    required this.planNo,
    required this.date,
    required this.customer,
    required this.item,
    this.itemId = '',
    this.categoryId,
    required this.cashPrice,
    required this.advance,
    required this.totalPrice,
    required this.costPrice,
    required this.status,
    this.cashSaleId,
  });

  bool get isCash => cashSaleId != null;

  /// Wapas hui naqd sale: [totalPrice] = kati hui raqam (piece stock mein wapas), poori munafa.
  bool get isReturned => status == 'returned';
  bool get hasCost => costPrice > 0 || isReturned;

  /// Qist qeemat − khareed (khareed na ho to 0).
  double get expectedProfit => isReturned ? _r(totalPrice) : (hasCost ? _r(totalPrice - costPrice) : 0);
}

class SaleTotals {
  final int count;
  final double cash;
  final double advance;
  final double total;
  final double cost;
  final double profit;
  final int withoutCost;
  final int cashCount;
  final double cashValue;
  const SaleTotals({
    this.count = 0,
    this.cash = 0,
    this.advance = 0,
    this.total = 0,
    this.cost = 0,
    this.profit = 0,
    this.withoutCost = 0,
    this.cashCount = 0,
    this.cashValue = 0,
  });

  int get planCount => count - cashCount;
}

List<SaleRow> saleRows(List<PlanView> views, {required int from, required int to}) {
  final out = <SaleRow>[
    for (final v in views)
      if (v.plan.createdAt >= from && v.plan.createdAt < to)
        SaleRow(
          planId: v.plan.id,
          planNo: v.plan.planNo,
          date: v.plan.createdAt,
          customer: v.customerName,
          item: v.itemTitle,
          itemId: v.item?.primaryId ?? '',
          categoryId: v.item?.categoryId,
          cashPrice: v.plan.cashPrice,
          advance: v.plan.advance,
          totalPrice: v.plan.totalPrice,
          costPrice: v.plan.costPrice,
          status: v.plan.status,
        )
  ];
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

/// Naqd sales -> sale rows (qist plans ke saath ek hi report).
List<SaleRow> cashSaleRows(List<CashSaleView> sales, {required int from, required int to}) => [
      for (final v in sales)
        if (v.sale.soldAt >= from && v.sale.soldAt < to)
          SaleRow(
            planId: 0,
            planNo: v.sale.saleNo,
            date: v.sale.soldAt,
            customer: '${v.sale.customerName.isEmpty ? 'Naqd' : v.sale.customerName}${v.sale.isReturned ? ' (wapas)' : ''}',
            item: v.itemTitle,
            itemId: v.item?.primaryId ?? '',
            categoryId: v.item?.categoryId,
            cashPrice: v.sale.kept,
            advance: v.sale.kept,
            totalPrice: v.sale.kept,
            costPrice: v.sale.isReturned ? 0 : v.sale.costPrice,
            status: v.sale.isReturned ? 'returned' : 'cash',
            cashSaleId: v.sale.id,
          )
    ];

SaleTotals saleTotals(List<SaleRow> rows) {
  var cash = 0.0, adv = 0.0, total = 0.0, cost = 0.0, profit = 0.0;
  var noCost = 0, cashN = 0;
  var cashV = 0.0;
  for (final r in rows) {
    if (r.isCash) {
      cashN++;
      cashV += r.totalPrice;
    }
    cash += r.cashPrice;
    adv += r.advance;
    total += r.totalPrice;
    if (r.isReturned) {
      profit += r.totalPrice;
    } else if (r.hasCost) {
      cost += r.costPrice;
      profit += r.totalPrice - r.costPrice;
    } else {
      noCost++;
    }
  }
  return SaleTotals(
      count: rows.length,
      cash: _r(cash),
      advance: _r(adv),
      total: _r(total),
      cost: _r(cost),
      profit: _r(profit),
      withoutCost: noCost,
      cashCount: cashN,
      cashValue: _r(cashV));
}

// ==================================================================== stock

class StockGroup {
  final String name;
  final int pieces;
  final double cost;
  final double cash;
  const StockGroup(this.name, this.pieces, this.cost, this.cash);
  double get margin => _r(cash - cost);
}

class StockPiece {
  final InstItem item;
  final String category;
  final int days;
  const StockPiece(this.item, this.category, this.days);
}

class StockReport {
  final List<StockGroup> byCategory;

  /// 0-30 / 31-90 / 91-180 / 180+ din.
  final List<StockGroup> byAge;
  final List<StockPiece> pieces;
  final StockGroup total;
  const StockReport({required this.byCategory, required this.byAge, required this.pieces, required this.total});
}

const stockAgeLabels = ['0-30', '31-90', '91-180', '180+'];

int stockAgeBucket(int days) => days <= 30 ? 0 : (days <= 90 ? 1 : (days <= 180 ? 2 : 3));

/// Sirf stock (in_stock) pieces. Din = khareed ki tareekh se (na ho to entry ki tareekh). Pieces: purane pehle.
StockReport stockReport(List<InstItem> items, Map<int, String> categoryNames, int today) {
  final inStock = items.where((i) => i.inStock).toList();
  final cat = <String, (int, double, double)>{};
  final age = List<(int, double, double)>.filled(4, (0, 0.0, 0.0));
  final pieces = <StockPiece>[];
  var n = 0;
  var cost = 0.0, cash = 0.0;
  for (final i in inStock) {
    final name = categoryNames[i.categoryId] ?? '—';
    final c = cat[name] ?? (0, 0.0, 0.0);
    cat[name] = (c.$1 + 1, c.$2 + i.costPrice, c.$3 + i.cashPrice);
    final since = i.purchaseDate > 0 ? i.purchaseDate : i.createdAt;
    final d = since > 0 ? _daysBetween(since, today) : 0;
    final days = d > 0 ? d : 0;
    final b = stockAgeBucket(days);
    final a = age[b];
    age[b] = (a.$1 + 1, a.$2 + i.costPrice, a.$3 + i.cashPrice);
    pieces.add(StockPiece(i, name, days));
    n++;
    cost += i.costPrice;
    cash += i.cashPrice;
  }
  final byCat = [for (final e in cat.entries) StockGroup(e.key, e.value.$1, _r(e.value.$2), _r(e.value.$3))]
    ..sort((a, b) => b.cost.compareTo(a.cost));
  pieces.sort((a, b) => b.days.compareTo(a.days));
  return StockReport(
    byCategory: byCat,
    byAge: [for (var k = 0; k < 4; k++) StockGroup(stockAgeLabels[k], age[k].$1, _r(age[k].$2), _r(age[k].$3))],
    pieces: pieces,
    total: StockGroup('', n, _r(cost), _r(cash)),
  );
}

// ==================================================================== due qisten

class DueEntry {
  final int planId;
  final String planNo;
  final String customer;
  final String phone;
  final String item;
  final int seq;
  final int dueDate;
  final double remaining;

  /// 0 = late nahi.
  final int daysLate;
  const DueEntry({
    required this.planId,
    required this.planNo,
    required this.customer,
    required this.phone,
    required this.item,
    required this.seq,
    required this.dueDate,
    required this.remaining,
    required this.daysLate,
  });
}

/// [from]..[to) mein aane wali na-adaa qisten (sirf jari plan). [withLate] = [from] se pehle ki baqi qisten bhi.
/// Tarteeb: tareekh, phir customer.
List<DueEntry> dueEntries(List<PlanView> views, {required int from, required int to, required int today, bool withLate = false}) {
  final out = <DueEntry>[];
  for (final v in views) {
    if (!v.plan.isActive) continue;
    for (final l in v.status.lines) {
      if (l.state == InstallmentState.paid || l.remaining <= 0.5) continue;
      final inRange = l.dueDate >= from && l.dueDate < to;
      final late = withLate && l.dueDate < from;
      if (!inRange && !late) continue;
      out.add(DueEntry(
        planId: v.plan.id,
        planNo: v.plan.planNo,
        customer: v.customerName,
        phone: v.customerPhone,
        item: v.itemTitle,
        seq: l.seq,
        dueDate: l.dueDate,
        remaining: l.remaining,
        daysLate: l.dueDate < today ? _daysBetween(l.dueDate, today) : 0,
      ));
    }
  }
  out.sort((a, b) {
    final c = a.dueDate.compareTo(b.dueDate);
    return c != 0 ? c : a.customer.toLowerCase().compareTo(b.customer.toLowerCase());
  });
  return out;
}

/// Din wise jor (tareekh -> raqam), tarteeb se.
List<(int, double, int)> dueByDay(List<DueEntry> entries) {
  final m = <int, (double, int)>{};
  for (final e in entries) {
    final d = DateTime.fromMillisecondsSinceEpoch(e.dueDate);
    final k = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    final c = m[k] ?? (0.0, 0);
    m[k] = (c.$1 + e.remaining, c.$2 + 1);
  }
  final keys = m.keys.toList()..sort();
  return [for (final k in keys) (k, _r(m[k]!.$1), m[k]!.$2)];
}

// ==================================================================== receivable

class ReceivableRow {
  final int customerId;
  final String name;
  final String phone;
  final int plans;
  final double remaining;
  final double overdue;
  final int daysLate;

  /// Agli na-adaa qist ki tareekh (0 = koi nahi).
  final int nextDue;
  const ReceivableRow({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.plans,
    required this.remaining,
    required this.overdue,
    required this.daysLate,
    required this.nextDue,
  });
}

/// Customer wise baqi (sirf jari plan). Tarteeb: zyada late raqam pehle, phir zyada baqi.
List<ReceivableRow> receivables(List<PlanView> views) {
  final m = <int, ReceivableRow>{};
  for (final v in views) {
    if (!v.plan.isActive || v.status.remaining <= 0.5) continue;
    final next = v.status.next?.dueDate ?? 0;
    final old = m[v.plan.customerId];
    m[v.plan.customerId] = ReceivableRow(
      customerId: v.plan.customerId,
      name: v.customerName,
      phone: v.customerPhone,
      plans: (old?.plans ?? 0) + 1,
      remaining: _r((old?.remaining ?? 0) + v.status.remaining),
      overdue: _r((old?.overdue ?? 0) + v.status.overdue),
      daysLate: old == null || v.status.daysLate > old.daysLate ? v.status.daysLate : old.daysLate,
      nextDue: old == null || old.nextDue == 0 || (next > 0 && next < old.nextDue) ? next : old.nextDue,
    );
  }
  final out = m.values.toList()
    ..sort((a, b) {
      final c = b.overdue.compareTo(a.overdue);
      return c != 0 ? c : b.remaining.compareTo(a.remaining);
    });
  return out;
}

// ==================================================================== position

class BusinessPosition {
  /// Customers se lena (jari plans ka baqi).
  final double receivable;

  /// Is mein se late.
  final double overdue;
  final double stockCost;
  final double stockCash;

  /// Suppliers ko dena.
  final double payable;

  /// App ke cash book ke hisaab se haath mein / bank mein.
  final double cash;
  final double bank;
  const BusinessPosition({
    this.receivable = 0,
    this.overdue = 0,
    this.stockCost = 0,
    this.stockCash = 0,
    this.payable = 0,
    this.cash = 0,
    this.bank = 0,
  });

  /// Lena + stock (khareed par) + cash + bank − dena.
  double get net => _r(receivable + stockCost + cash + bank - payable);
}
