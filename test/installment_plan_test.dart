import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/installment/inst_plan_math.dart';

void main() {
  group('quotePlan', () {
    test('percent profit on amount after advance, rounded to 10', () {
      final q = quotePlan(cashPrice: 50000, advance: 10000, profitMode: profitPercent, profitValue: 30, count: 12, roundTo: 10);
      expect(q.financed, 40000);
      expect(q.profit, 12000);
      expect(q.installmentTotal, 52000);
      expect(q.totalPrice, 62000);
      expect(q.each, 4340); // 52000 / 12 = 4333.33 -> 4340
      expect(q.last, 52000 - 4340 * 11); // 4260
      expect(q.amounts.fold<double>(0, (a, b) => a + b), 52000);
      expect(q.amounts.length, 12);
    });

    test('fixed profit, no rounding', () {
      final q = quotePlan(cashPrice: 30000, advance: 0, profitMode: profitFixed, profitValue: 6000, count: 6);
      expect(q.installmentTotal, 36000);
      expect(q.each, 6000);
      expect(q.last, 6000);
    });

    test('big rounding on small amount falls back to rounding down', () {
      final q = quotePlan(cashPrice: 1000, advance: 0, profitMode: profitPercent, profitValue: 0, count: 6, roundTo: 500);
      // ceil -> 500 × 5 = 2500 > 1000 (last minus) -> floor 0 -> rounding chhor: 166 × 5, last 170
      expect(q.last > 0, isTrue);
      expect(q.amounts.fold<double>(0, (a, b) => a + b), 1000);
    });

    test('single installment', () {
      final q = quotePlan(cashPrice: 10000, advance: 2000, profitMode: profitPercent, profitValue: 10, count: 1, roundTo: 100);
      expect(q.amounts, [8800]);
    });

    test('bad input', () {
      expect(() => quotePlan(cashPrice: 0, advance: 0, profitMode: profitPercent, profitValue: 0, count: 3), throwsArgumentError);
      expect(() => quotePlan(cashPrice: 1000, advance: 1000, profitMode: profitPercent, profitValue: 0, count: 3), throwsArgumentError);
      expect(() => quotePlan(cashPrice: 1000, advance: 0, profitMode: profitPercent, profitValue: -1, count: 3), throwsArgumentError);
      expect(() => quotePlan(cashPrice: 1000, advance: 0, profitMode: profitPercent, profitValue: 0, count: 0), throwsArgumentError);
    });
  });

  group('dates', () {
    test('monthly keeps the day, clamps short months', () {
      final first = dayStart(DateTime(2026, 1, 31));
      expect(DateTime.fromMillisecondsSinceEpoch(dueDateOf(first, freqMonthly, 1)), DateTime(2026, 2, 28));
      expect(DateTime.fromMillisecondsSinceEpoch(dueDateOf(first, freqMonthly, 2)), DateTime(2026, 3, 31));
      expect(DateTime.fromMillisecondsSinceEpoch(dueDateOf(first, freqMonthly, 12)), DateTime(2027, 1, 31));
    });

    test('weekly and fortnightly', () {
      final first = dayStart(DateTime(2026, 11, 10));
      expect(DateTime.fromMillisecondsSinceEpoch(dueDateOf(first, freqWeekly, 3)), DateTime(2026, 12, 1));
      expect(DateTime.fromMillisecondsSinceEpoch(dueDateOf(first, freqFortnightly, 2)), DateTime(2026, 12, 10));
    });

    test('leap year', () {
      expect(addMonthsClamped(DateTime(2027, 12, 29), 2), DateTime(2028, 2, 29));
    });
  });

  group('planStatus', () {
    final d1 = dayStart(DateTime(2026, 9, 10));
    final d2 = dayStart(DateTime(2026, 10, 10));
    final d3 = dayStart(DateTime(2026, 11, 10));
    final d4 = dayStart(DateTime(2026, 12, 10));
    final sched = [(d1, 5000.0), (d2, 5000.0), (d3, 5000.0), (d4, 5000.0)];

    test('payments fill oldest first; overdue and days late', () {
      final today = dayStart(DateTime(2026, 11, 13));
      final s = planStatus(schedule: sched, paidInstallments: 7000, today: today);
      expect(s.lines[0].state, InstallmentState.paid);
      expect(s.lines[1].state, InstallmentState.overdue);
      expect(s.lines[1].paid, 2000);
      expect(s.lines[2].state, InstallmentState.overdue);
      expect(s.lines[3].state, InstallmentState.upcoming);
      expect(s.overdue, 8000);
      expect(s.overdueCount, 2);
      expect(s.daysLate, 34); // 10 Oct -> 13 Nov
      expect(s.remaining, 13000);
      expect(s.next!.seq, 2);
    });

    test('due today and partial upcoming', () {
      final s = planStatus(schedule: sched, paidInstallments: 12000, today: d3);
      expect(s.lines[2].state, InstallmentState.dueToday);
      expect(s.dueNow, 3000);
      expect(s.overdue, 0);
      final s2 = planStatus(schedule: sched, paidInstallments: 17000, today: d3);
      expect(s2.lines[3].state, InstallmentState.partial);
      expect(s2.dueNow, 0);
    });

    test('fully paid', () {
      final s = planStatus(schedule: sched, paidInstallments: 20000, today: d4);
      expect(s.fullyPaid, isTrue);
      expect(s.next, isNull);
      expect(s.paid, 20000);
    });
  });

  test('suggested fine counts late installments past grace, minus fines taken', () {
    final d1 = dayStart(DateTime(2026, 10, 1));
    final d2 = dayStart(DateTime(2026, 11, 10));
    final today = dayStart(DateTime(2026, 11, 12));
    final st = planStatus(schedule: [(d1, 1000.0), (d2, 1000.0)], paidInstallments: 0, today: today);
    expect(suggestedFine(status: st, lateFee: 200, graceDays: 3, today: today), 200); // sirf pehli 3 din se zyada late
    expect(suggestedFine(status: st, lateFee: 200, graceDays: 0, today: today), 400);
    expect(suggestedFine(status: st, lateFee: 200, graceDays: 0, today: today, finesAlreadyTaken: 300), 100);
    expect(suggestedFine(status: st, lateFee: 0, graceDays: 0, today: today), 0);
  });

  test('receipt text', () {
    final t = receiptText(
      shopName: 'Hanna Mobile',
      planNo: 'Q-0007',
      customerName: 'Ali',
      itemTitle: 'Samsung A15',
      amount: 4340,
      fine: 200,
      method: 'cash',
      paidAt: DateTime(2026, 11, 13).millisecondsSinceEpoch,
      remaining: 0,
      nextDue: null,
      nextAmount: 0,
    );
    expect(t, contains('Q-0007'));
    expect(t, contains('Rs 4340'));
    expect(t, contains('Late fine: Rs 200'));
    expect(t, contains('Plan complete'));
    expect(parseIdList('[3, 5]'), [3, 5]);
    expect(parseIdList('bad'), isEmpty);
  });

  group('rescheduleLines (Step 17)', () {
    final d0 = DateTime(2026, 1, 10).millisecondsSinceEpoch;
    final sched = [for (var i = 0; i < 6; i++) (dueDateOf(d0, freqMonthly, i), 1000.0)];
    final f = DateTime(2026, 6, 1).millisecondsSinceEpoch;

    test('keeps paid lines, splits partial, spreads rest + extra', () {
      final l = rescheduleLines(schedule: sched, paid: 2500, count: 4, firstDue: f, frequency: freqMonthly, extra: 500, roundTo: 10);
      expect(l.take(3).map((x) => x.$2).toList(), [1000, 1000, 500]);
      expect(l[2].$1, sched[2].$1);
      final fresh = l.skip(3).toList();
      expect(fresh.length, 4);
      expect(fresh.first.$1, f);
      expect(fresh.map((x) => x.$2).toList(), [1000, 1000, 1000, 1000]); // 3500 + 500
      expect(l.fold<double>(0, (a, x) => a + x.$2), 6500);
    });

    test('rounding leftover goes to last; weekly dates', () {
      final l = rescheduleLines(schedule: sched, paid: 0, count: 7, firstDue: f, frequency: freqWeekly, roundTo: 10);
      expect(l.length, 7);
      expect(l.first.$2, 860); // 6000/7 = 857.1 -> 860
      expect(l.last.$2, 6000 - 860 * 6);
      expect(l[1].$1 - l[0].$1, const Duration(days: 7).inMilliseconds);
    });

    test('errors', () {
      expect(() => rescheduleLines(schedule: sched, paid: 6000, count: 2, firstDue: f, frequency: freqMonthly), throwsArgumentError);
      expect(() => rescheduleLines(schedule: sched, paid: 0, count: 0, firstDue: f, frequency: freqMonthly), throwsArgumentError);
      expect(() => rescheduleLines(schedule: sched, paid: 5000, count: 2, firstDue: f, frequency: freqMonthly, extra: -1000),
          throwsArgumentError); // baqi 0
      // Exchange: sasta piece => baqi kam.
      final l = rescheduleLines(schedule: sched, paid: 2000, count: 2, firstDue: f, frequency: freqMonthly, extra: -1000);
      expect(l.skip(2).map((x) => x.$2).toList(), [1500, 1500]);
    });
  });

  test('daily plan (Step 30): har din ek qist, 400 tak', () {
    final d0 = DateTime(2026, 12, 30).millisecondsSinceEpoch;
    expect(DateTime.fromMillisecondsSinceEpoch(dueDateOf(d0, freqDaily, 3)), DateTime(2027, 1, 2));
    final q = quotePlan(cashPrice: 10000, advance: 1000, profitMode: profitFixed, profitValue: 0, count: 90, frequency: freqDaily);
    expect(q.count, 90);
    expect(() => quotePlan(cashPrice: 10000, advance: 0, profitMode: profitFixed, profitValue: 0, count: 90), throwsArgumentError);
    expect(() => quotePlan(cashPrice: 10000, advance: 0, profitMode: profitFixed, profitValue: 0, count: 401, frequency: freqDaily),
        throwsArgumentError);
  });
}
