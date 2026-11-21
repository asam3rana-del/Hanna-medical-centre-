import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/installment/inst_models.dart';
import 'package:hanna_installment/installment/inst_scan.dart';

void main() {
  const a15 = InstItem(id: 1, categoryId: 1, brand: 'Samsung', model: 'A15', idValues: {'IMEI 1': '356789012345678', 'IMEI 2': '356789012345686'});
  const sold = InstItem(id: 2, categoryId: 1, brand: 'Vivo', model: 'Y03', idValues: {'IMEI 1': '861234567890123'}, status: itemSold);
  const bike = InstItem(id: 3, categoryId: 2, brand: 'Honda', model: 'CD-70', idValues: {'Engine No.': 'JA05E-1234567', 'Chassis No.': 'ABC123456'});
  final all = [a15, sold, bike];

  test('IMEI printed in parts on a box sticker', () {
    final c = scanCandidates('Samsung Galaxy A15\nIMEI 1: 35 678901 234567 8\nS/N R58X12');
    expect(c, contains('356789012345678'));
    expect(matchScan(all, c).single.id, 1);
  });

  test('second IMEI and barcode gun input', () {
    expect(matchScan(all, scanCandidates('356789012345686')).single.id, 1);
    expect(matchScan(all, scanCandidates('861234567890123')).single.status, itemSold);
  });

  test('engine number with dash, any case', () {
    expect(matchScan(all, scanCandidates('Engine: ja05e 1234567')).single.id, 3);
    expect(matchScan(all, scanCandidates('chassis abc123456')).single.id, 3);
  });

  test('partial IMEI (8+ digits) still matches; junk does not', () {
    expect(matchScan(all, scanCandidates('IMEI ...8901234567')).single.id, 1);
    expect(matchScan(all, scanCandidates('Price 25000 Rs')), isEmpty);
    expect(scanCandidates(''), isEmpty);
  });

  test('in-stock first when two pieces match', () {
    const twin = InstItem(id: 9, categoryId: 1, model: 'A15', idValues: {'IMEI 1': '356789012345678'}, status: itemSold);
    final r = matchScan([twin, a15], scanCandidates('356789012345678'));
    expect(r.first.id, 1);
  });
}
