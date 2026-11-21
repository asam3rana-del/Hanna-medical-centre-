import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/installment/inst_plan_repository.dart';
import 'package:hanna_installment/installment/inst_trend_chart.dart';

void main() {
  test('monthStarts: last 6 months, oldest first, across a year', () {
    final m = monthStarts(DateTime(2026, 2, 17), 6);
    expect(m.length, 6);
    expect(DateTime.fromMillisecondsSinceEpoch(m.first), DateTime(2025, 9, 1));
    expect(DateTime.fromMillisecondsSinceEpoch(m.last), DateTime(2026, 2, 1));
  });

  test('shortRs', () {
    expect(shortRs(850), '850');
    expect(shortRs(85000), '85K');
    expect(shortRs(130000), '1.3L');
    expect(shortRs(2500000), '25L');
    expect(shortRs(15000000), '1.5Cr');
    expect(shortRs(-4000), '-4K');
  });
}
