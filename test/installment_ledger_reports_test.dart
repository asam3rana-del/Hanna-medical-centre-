import 'package:flutter_test/flutter_test.dart';

import 'package:hanna_installment/installment/inst_cash_sale_repository.dart';
import 'package:hanna_installment/installment/inst_ledger_reports.dart';
import 'package:hanna_installment/installment/inst_models.dart';
import 'package:hanna_installment/installment/inst_plan_math.dart';
import 'package:hanna_installment/installment/inst_plan_repository.dart';

int day(int y, int m, int d) => DateTime(y, m, d).millisecondsSinceEpoch;

PlanView view({
  required int id,
  required int customerId,
  required String name,
  required List<(int, double)> schedule,
  required double paid,
  required int today,
  int createdAt = 0,
  double cash = 50000,
  double cost = 40000,
  double total = 60000,
  String status = 'active',
}) =>
    PlanView(
      plan: InstPlan.fromMap({
        'id': id,
        'planNo': 'Q-$id',
        'customerId': customerId,
        'itemId': id,
        'cashPrice': cash,
        'costPrice': cost,
        'totalPrice': total,
        'advance': 10000,
        'status': status,
        'createdAt': createdAt,
      }),
      customerName: name,
      customerPhone: '0300',
      item: InstItem(id: id, categoryId: 1, model: 'A15', idValues: const {'IMEI 1': '123456789'}),
      schedule: schedule,
      payments: const [],
      status: planStatus(schedule: schedule, paidInstallments: paid, today: today),
    );

void main() {
  final today = day(2026, 11, 13);

  test('due entries: range, late, order; receivables grouped by customer', () {
    final views = [
      view(id: 1, customerId: 1, name: 'Ali', today: today, paid: 10000, schedule: [
        (day(2026, 10, 1), 10000), // paid
        (day(2026, 11, 1), 10000), // late 12 days
        (day(2026, 12, 1), 10000),
      ]),
      view(id: 2, customerId: 1, name: 'Ali', today: today, paid: 0, schedule: [(day(2026, 11, 15), 5000)]),
      view(id: 3, customerId: 2, name: 'Bilal', today: today, paid: 0, schedule: [(day(2026, 11, 14), 7000)]),
      view(id: 4, customerId: 3, name: 'Closed', today: today, paid: 0, status: 'completed', schedule: [(day(2026, 11, 14), 9000)]),
    ];
    final nov = dueEntries(views, from: day(2026, 11, 13), to: day(2026, 12, 1), today: today);
    expect(nov.map((e) => e.customer), ['Bilal', 'Ali']);
    final withLate = dueEntries(views, from: day(2026, 11, 13), to: day(2026, 12, 1), today: today, withLate: true);
    expect(withLate.map((e) => (e.planNo, e.daysLate)), [('Q-1', 12), ('Q-3', 0), ('Q-2', 0)]);
    expect(dueByDay(withLate).map((d) => d.$2), [10000.0, 7000.0, 5000.0]);

    final rec = receivables(views);
    expect(rec.map((r) => r.name), ['Ali', 'Bilal']);
    expect(rec.first.plans, 2);
    expect(rec.first.remaining, 25000);
    expect(rec.first.overdue, 10000);
    expect(rec.first.daysLate, 12);
    expect(rec.first.nextDue, day(2026, 11, 1));
  });

  test('sale rows / totals in period', () {
    final views = [
      view(id: 1, customerId: 1, name: 'A', today: today, paid: 0, schedule: const [], createdAt: day(2026, 11, 2)),
      view(id: 2, customerId: 2, name: 'B', today: today, paid: 0, schedule: const [], createdAt: day(2026, 11, 5), cost: 0),
      view(id: 3, customerId: 3, name: 'C', today: today, paid: 0, schedule: const [], createdAt: day(2026, 10, 30)),
    ];
    final rows = saleRows(views, from: day(2026, 11, 1), to: day(2026, 12, 1));
    expect(rows.map((r) => r.planNo), ['Q-2', 'Q-1']);
    final t = saleTotals(rows);
    expect(t.count, 2);
    expect(t.total, 120000);
    expect(t.profit, 20000); // sirf Q-1 (Q-2 ki khareed nahi)
    expect(t.withoutCost, 1);
  });

  test('cash sales join the sale report', () {
    final sales = [
      CashSaleView(InstCashSale(id: 7, saleNo: 'N-AA0007', itemId: 9, price: 47000, costPrice: 40000, soldAt: day(2026, 11, 6)),
          InstItem(id: 9, categoryId: 1, model: 'A15')),
      CashSaleView(InstCashSale(id: 8, saleNo: 'N-AA0008', itemId: 10, price: 5000, soldAt: day(2026, 10, 6)), null),
      CashSaleView(
          InstCashSale(
              id: 9, saleNo: 'N-AA0009', itemId: 11, price: 30000, costPrice: 25000, soldAt: day(2026, 11, 8),
              returnedAt: day(2026, 11, 9), refund: 28000),
          null),
    ];
    final rows = cashSaleRows(sales, from: day(2026, 11, 1), to: day(2026, 12, 1));
    expect(rows.length, 2);
    final sold = rows.firstWhere((r) => r.cashSaleId == 7);
    expect(sold.isCash, isTrue);
    expect(sold.customer, 'Naqd');
    final ret = rows.firstWhere((r) => r.cashSaleId == 9);
    expect(ret.isReturned, isTrue);
    expect(ret.totalPrice, 2000); // 30000 - 28000 wapas
    expect(ret.expectedProfit, 2000);
    final t = saleTotals(rows);
    expect(t.cashCount, 2);
    expect(t.cashValue, 49000);
    expect(t.planCount, 0);
    expect(t.profit, 9000); // 7000 + 2000
    expect(t.withoutCost, 0);
  });

  test('stock report: only in-stock, by category and age', () {
    final items = [
      InstItem(id: 1, categoryId: 1, model: 'A15', costPrice: 40000, cashPrice: 48000, purchaseDate: day(2026, 11, 1)),
      InstItem(id: 2, categoryId: 1, model: 'A05', costPrice: 25000, cashPrice: 30000, purchaseDate: day(2026, 5, 1)),
      InstItem(id: 3, categoryId: 2, model: 'CD-70', costPrice: 150000, cashPrice: 170000, purchaseDate: day(2026, 9, 1)),
      InstItem(id: 4, categoryId: 1, model: 'Sold', costPrice: 1, cashPrice: 1, status: itemSold),
    ];
    final r = stockReport(items, {1: 'Mobile', 2: 'Motorcycle'}, today);
    expect(r.total.pieces, 3);
    expect(r.total.cost, 215000);
    expect(r.byCategory.map((g) => (g.name, g.pieces)), [('Motorcycle', 1), ('Mobile', 2)]);
    expect(r.byAge.map((g) => g.pieces), [1, 1, 0, 1]); // 12, 73, 196 din
    expect(r.pieces.first.item.model, 'A05');
    expect(stockAgeBucket(30), 0);
    expect(stockAgeBucket(31), 1);
    expect(stockAgeBucket(181), 3);
  });

  test('business position net', () {
    const p = BusinessPosition(receivable: 100000, stockCost: 50000, payable: 30000, cash: 5000, bank: 1000);
    expect(p.net, 126000);
  });
}
