import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/installment/inst_csv.dart';

void main() {
  test('csv: money becomes numbers, commas quoted, formulas blocked', () {
    final t = csvText(
      title: 'Sale report',
      sub: '01-11-2026 - 30-11-2026',
      summary: [('Total', 'Rs 125,000')],
      headers: ['Customer', 'Item', 'Amount'],
      rows: [
        ['Ali, Khan', 'A15', 'Rs 52,000'],
        ['=HYPERLINK("x")', 'Y03', 'Rs -1,200.50'],
        ['علی', 'He said "hi"', '-'],
      ],
    );
    final lines = t.trim().split('\n');
    expect(lines[0], 'Sale report');
    expect(lines[2], 'Total,125000');
    expect(lines[3], '');
    expect(lines[4], 'Customer,Item,Amount');
    expect(lines[5], '"Ali, Khan",A15,52000');
    expect(lines[6], '"\'=HYPERLINK(""x"")",Y03,-1200.50');
    expect(lines[7], 'علی,"He said ""hi""",\'-');
  });
}
