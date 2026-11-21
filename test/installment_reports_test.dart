import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/installment/inst_plan_math.dart';
import 'package:hanna_installment/installment/inst_reports.dart';

void main() {
  int day(int y, int m, int d) => dayStart(DateTime(y, m, d));

  test('aging buckets per installment due date', () {
    final today = day(2026, 11, 13);
    final sched = [
      (day(2026, 7, 1), 1000.0), // 135 din -> 90+
      (day(2026, 9, 1), 1000.0), // 73 -> 61-90
      (day(2026, 10, 1), 1000.0), // 43 -> 31-60
      (day(2026, 11, 1), 1000.0), // 12 -> 1-30
      (day(2026, 11, 13), 1000.0), // aaj -> late nahi
      (day(2026, 12, 1), 1000.0), // aane wali
    ];
    final st = planStatus(schedule: sched, paidInstallments: 500, today: today);
    final a = agingOf([st], today);
    expect(a.d90plus, 500); // pehli qist ka aadha ada
    expect(a.d61to90, 1000);
    expect(a.d31to60, 1000);
    expect(a.d1to30, 1000);
    expect(a.notLate, 2000);
    expect(a.late, 3500);
    expect(a.total, 5500);
  });

  test('period report: only rows inside the period', () {
    final (from, to) = monthRange(DateTime(2026, 11, 20));
    expect(DateTime.fromMillisecondsSinceEpoch(from), DateTime(2026, 11, 1));
    expect(DateTime.fromMillisecondsSinceEpoch(to), DateTime(2026, 12, 1));
    final nov5 = DateTime(2026, 11, 5, 14).millisecondsSinceEpoch;
    final r = periodReport(
      payments: [
        PayRow(paidAt: nov5, kind: payAdvance, amount: 10000),
        PayRow(paidAt: nov5, kind: payInstallment, amount: 4000, fine: 200, method: 'bank'),
        PayRow(paidAt: DateTime(2026, 10, 30).millisecondsSinceEpoch, kind: payInstallment, amount: 999),
      ],
      plans: [
        PlanRow(createdAt: nov5, cashPrice: 50000, costPrice: 42000, totalPrice: 62000, advance: 10000, status: planActive),
        PlanRow(createdAt: nov5, cashPrice: 20000, costPrice: 0, totalPrice: 25000, advance: 0, status: planActive),
        PlanRow(createdAt: DateTime(2026, 12, 2).millisecondsSinceEpoch, cashPrice: 1, costPrice: 0, totalPrice: 1, advance: 0, status: planActive),
      ],
      closures: [(nov5, planCompleted), (nov5, planRepossessed), (DateTime(2026, 9, 1).millisecondsSinceEpoch, planCompleted)],
      from: from,
      to: to,
    );
    expect(r.collectedAdvance, 10000);
    expect(r.collectedInstallments, 4000);
    expect(r.collectedFines, 200);
    expect(r.collectedTotal, 14200);
    expect(r.cashIn, 10000);
    expect(r.bankIn, 4200);
    expect(r.paymentCount, 2);
    expect(r.newPlans, 2);
    expect(r.newCashValue, 70000);
    expect(r.newTotalValue, 87000);
    expect(r.newExpectedProfit, 20000); // sirf jis ki khareed likhi (62000 − 42000)
    expect(r.completed, 1);
    expect(r.repossessed, 1);
    expect(r.byDay[day(2026, 11, 5)], 14200);
  });

  test('dueWithin includes late and the next N days', () {
    final today = day(2026, 11, 13);
    final st = planStatus(
      schedule: [(day(2026, 11, 1), 1000.0), (day(2026, 11, 18), 1000.0), (day(2026, 12, 20), 1000.0)],
      paidInstallments: 0,
      today: today,
    );
    expect(dueWithin(st, today, 7), 2000);
    expect(dueWithin(st, today, 1), 1000);
    expect(dueWithin(st, today, 60), 3000);
  });

  test('profit share: proportional to collection; unknown cost => null', () {
    // 50,000 ka mobile 62,000 mein qist par: munafa 12,000 = 19.35% har wasooli ka
    expect(profitShare(collected: 62000, totalPrice: 62000, costPrice: 50000), 12000);
    expect(profitShare(collected: 10000, totalPrice: 62000, costPrice: 50000), 1935.48);
    expect(profitShare(collected: 1000, totalPrice: 50000, costPrice: 0), isNull);
    expect(profitShare(collected: 1000, totalPrice: 40000, costPrice: 50000), -250); // ghate ka sauda
  });

  test('profit report: realized + fines - expenses, only inside the period', () {
    final nov = DateTime(2026, 11, 5).millisecondsSinceEpoch;
    final oct = DateTime(2026, 10, 5).millisecondsSinceEpoch;
    final (from, to) = monthRange(DateTime(2026, 11, 1));
    final r = profitReport(
      payments: [
        ProfitPayRow(paidAt: nov, amount: 10000, totalPrice: 62000, costPrice: 50000),
        ProfitPayRow(paidAt: nov, amount: 5000, fine: 300, totalPrice: 62000, costPrice: 50000),
        ProfitPayRow(paidAt: nov, amount: 2000, totalPrice: 20000, costPrice: 0), // khareed nahi likhi
        ProfitPayRow(paidAt: oct, amount: 99999, totalPrice: 62000, costPrice: 50000),
      ],
      expenses: [(nov, 'Salary', 8000), (nov, 'Rent', 5000), (nov, ' ', 100), (oct, 'Rent', 5000)],
      from: from,
      to: to,
    );
    expect(r.collectedWithCost, 15000);
    expect(r.collectedWithoutCost, 2000);
    expect(r.realizedProfit, 2903.23); // 15000 × 12000/62000
    expect(r.fines, 300);
    expect(r.grossProfit, 3203.23);
    expect(r.expenses, {'Salary': 8000.0, 'Rent': 5000.0, 'Other': 100.0});
    expect(r.expenseTotal, 13100);
    expect(r.netProfit, -9896.77);
  });

  test('discount on full settlement: lowers profit by discount x cost share, not counted as collection', () {
    final nov = DateTime(2026, 11, 5).millisecondsSinceEpoch;
    final (from, to) = monthRange(DateTime(2026, 11, 1));
    // Qist qeemat 60000, khareed 40000 (munafa 1/3). Wasooli 50000 + chhoot 10000.
    final r = profitReport(
      payments: [
        ProfitPayRow(paidAt: nov, amount: 50000, totalPrice: 60000, costPrice: 40000),
        ProfitPayRow(paidAt: nov, amount: 10000, totalPrice: 60000, costPrice: 40000, discount: true),
      ],
      expenses: const [],
      from: from,
      to: to,
    );
    expect(r.collectedWithCost, 50000);
    expect(r.discounts, 10000);
    // Asal: (60000 - 10000) - 40000 = 10000
    expect(r.realizedProfit, 10000);
    final pr = periodReport(
      payments: [
        PayRow(paidAt: nov, kind: payInstallment, amount: 50000, method: 'cash'),
        PayRow(paidAt: nov, kind: payDiscount, amount: 10000, method: 'cash'),
      ],
      plans: const [],
      closures: const [],
      from: from,
      to: to,
    );
    expect(pr.collectedInstallments, 50000);
    expect(pr.cashIn, 50000);
    expect(pr.paymentCount, 1);
    expect(pr.discounts, 10000);
  });

  test('profit report: cash sales add their profit; no-cost sales counted apart', () {
    final nov = DateTime(2026, 11, 5).millisecondsSinceEpoch;
    final oct = DateTime(2026, 10, 5).millisecondsSinceEpoch;
    final (from, to) = monthRange(DateTime(2026, 11, 1));
    final r = profitReport(
      payments: const [],
      expenses: const [],
      from: from,
      to: to,
      cashSales: [(nov, 47000.0, 40000.0), (nov, 10000.0, 0.0), (oct, 99999.0, 1.0)],
      keptOnReturns: [(nov, 2000.0), (oct, 5000.0)],
    );
    expect(r.cashSales, 59000); // 47000 + 10000 + 2000 (wapsi par kati raqam)
    expect(r.cashSaleProfit, 9000); // 7000 + 2000
    expect(r.collectedWithoutCost, 10000);
    expect(r.grossProfit, 9000);
    expect(r.netProfit, 9000);
  });

  test('rate change: set / add / percent, rounding, never negative', () {
    expect(applyRateChange(52000, RateChangeMode.setTo, 54000), 54000);
    expect(applyRateChange(52000, RateChangeMode.addAmount, -1500), 50500);
    expect(applyRateChange(52000, RateChangeMode.percent, 5), 54600);
    expect(applyRateChange(52300, RateChangeMode.percent, -3, roundTo: 100), 50700); // 50731 -> 50700
    expect(applyRateChange(1000, RateChangeMode.addAmount, -5000), 0);
    expect(const StockValue(3, 150000, 171000).margin, 21000);
  });
}
