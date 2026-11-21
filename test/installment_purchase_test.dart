import 'package:flutter_test/flutter_test.dart';

import 'package:hanna_installment/installment/inst_purchase_repository.dart';

void main() {
  final day1 = DateTime(2026, 11, 1).millisecondsSinceEpoch;
  final day2 = DateTime(2026, 11, 5).millisecondsSinceEpoch;

  test('supplier ledger: opening, bills, payments and running balance', () {
    const s = InstSupplier(id: 1, name: 'Ali Traders', openingBalance: 5000, createdAt: 0);
    final bills = [
      InstPurchase(id: 1, billNo: 'K-1', supplierId: 1, purchaseDate: day1, total: 80000),
      InstPurchase(id: 2, billNo: 'K-2', supplierId: 1, purchaseDate: day2, total: 20000),
    ];
    final pays = [
      // Same day as bill K-1 (later in the day) — bill comes first.
      InstSupplierPayment(id: 1, supplierId: 1, purchaseId: 1, amount: 30000, paidAt: day1 + 3600000),
      InstSupplierPayment(id: 2, supplierId: 1, amount: 50000, paidAt: day2 + 7200000),
    ];
    final lines = buildSupplierLedger(s, bills, pays, {1: 'K-1', 2: 'K-2'});
    expect(lines.map((l) => l.label), ['Purana baqi', 'Bill K-1', 'Adaigi (K-1)', 'Bill K-2', 'Adaigi']);
    expect(lines.map((l) => l.balance), [5000.0, 85000.0, 55000.0, 75000.0, 25000.0]);

    final row = InstSupplierRow(supplier: s, purchased: 100000, paid: 80000);
    expect(row.balance, lines.last.balance);
  });

  test('payment before a bill on the same day still sorts after it', () {
    const s = InstSupplier(id: 1, name: 'X');
    final bills = [InstPurchase(id: 1, billNo: 'K-1', supplierId: 1, purchaseDate: day1, total: 1000)];
    final pays = [InstSupplierPayment(id: 1, supplierId: 1, amount: 400, paidAt: day1 - 1 + 1)];
    final lines = buildSupplierLedger(s, bills, pays, const {});
    expect(lines.map((l) => l.balance), [1000.0, 600.0]);
  });

  test('returns to supplier lower the balance and show in the ledger', () {
    const s = InstSupplier(id: 1, name: 'Ali Traders');
    final bills = [InstPurchase(id: 1, billNo: 'K-1', supplierId: 1, purchaseDate: day1, total: 80000)];
    final rets = [PurchaseReturn(id: 1, supplierId: 1, purchaseId: 1, itemId: 5, amount: 40000, returnedAt: day2, itemTitle: 'A15')];
    final lines = buildSupplierLedger(s, bills, const [], {1: 'K-1'}, returns: rets);
    expect(lines.map((l) => l.label), ['Bill K-1', 'Wapsi: A15']);
    expect(lines.last.balance, 40000);
    expect(lines.last.ret?.itemId, 5);
    const row = InstSupplierRow(supplier: s, purchased: 80000, paid: 10000, returned: 40000);
    expect(row.balance, 30000);
    final b = InstPurchase(id: 1, billNo: 'K-1', supplierId: 1, purchaseDate: day1, total: 80000, paid: 10000, returned: 40000);
    expect(b.due, 30000);
  });

  test('bill due = total - paid', () {
    final b = InstPurchase(id: 1, billNo: 'K-1', supplierId: 1, purchaseDate: day1, total: 80000, paid: 30000);
    expect(b.due, 50000);
  });
}
