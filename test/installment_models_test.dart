import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/installment/inst_models.dart';

void main() {
  group('CNIC', () {
    test('format and validate', () {
      expect(formatCnic('3520212345671'), '35202-1234567-1');
      expect(formatCnic('35202-1234567-1'), '35202-1234567-1');
      expect(formatCnic(' 123 '), '123');
      expect(cnicValid(''), isTrue);
      expect(cnicValid('35202-1234567-1'), isTrue);
      expect(cnicValid('35202-123456'), isFalse);
      expect(cnicDigits('35202-1234567-1'), '3520212345671');
    });

    test('phone', () {
      expect(phoneValid(''), isTrue);
      expect(phoneValid('0300 1234567'), isTrue);
      expect(phoneValid('+92 300 1234567'), isTrue);
      expect(phoneValid('042-1234567'), isFalse);
      expect(phoneValid('0300123'), isFalse);
    });
  });

  group('category', () {
    test('parseIdFields trims, drops empty and duplicates', () {
      expect(parseIdFields('IMEI 1, IMEI 2, ,imei 1'), ['IMEI 1', 'IMEI 2']);
      expect(parseIdFields(''), isEmpty);
      expect(parseIdFields('Engine No.\nChassis No.'), ['Engine No.', 'Chassis No.']);
    });

    test('map round trip, broken JSON is safe', () {
      const c = InstCategory(id: 3, name: 'Mobile', idFields: ['IMEI 1', 'IMEI 2'], sortOrder: 1);
      final back = InstCategory.fromMap(c.toMap());
      expect(back.name, 'Mobile');
      expect(back.idFields, ['IMEI 1', 'IMEI 2']);
      expect(InstCategory.fromMap({'name': 'X', 'idFields': '{bad'}).idFields, isEmpty);
    });

    test('defaults include mobile and motorcycle', () {
      final names = defaultInstCategories.map((e) => e.$1).toList();
      expect(names, containsAll(['Mobile', 'Motorcycle', 'Furniture']));
      expect(defaultInstCategories.first.$2, ['IMEI 1', 'IMEI 2']);
    });
  });

  group('item', () {
    const phone = InstItem(
      id: 1,
      categoryId: 1,
      brand: 'Samsung',
      model: 'A15 128GB',
      color: 'Black',
      idValues: {'IMEI 1': '356789-01-234567-8', 'IMEI 2': '356789012345684'},
      cashPrice: 52000,
    );

    test('map round trip', () {
      final back = InstItem.fromMap(phone.toMap());
      expect(back.title, 'Samsung A15 128GB');
      expect(back.idValues['IMEI 1'], '356789-01-234567-8');
      expect(back.inStock, isTrue);
      expect(back.primaryId, 'IMEI 1: 356789-01-234567-8');
    });

    test('search by model words and by IMEI without dashes', () {
      expect(phone.matches('samsung a15'), isTrue);
      expect(phone.matches('a15 black'), isTrue);
      expect(phone.matches('356789012345678'), isTrue);
      expect(phone.matches('2345684'), isTrue);
      expect(phone.matches('iphone'), isFalse);
      expect(phone.matches(''), isTrue);
    });

    test('duplicate IMEI across fields and pieces', () {
      const other = InstItem(id: 2, categoryId: 1, model: 'A15', idValues: {'IMEI 1': '356789012345684'});
      expect(findDuplicateId(other, [phone]), 'IMEI 1: 356789012345684');
      // apne aap se takrao nahi
      expect(findDuplicateId(phone, [phone]), isNull);
      const fresh = InstItem(categoryId: 1, model: 'A05', idValues: {'IMEI 1': '111122223333444'});
      expect(findDuplicateId(fresh, [phone, other]), isNull);
      // bohat chhota number nazar-andaz
      const tiny = InstItem(categoryId: 1, model: 'X', idValues: {'Serial No.': '12'});
      const tiny2 = InstItem(id: 9, categoryId: 1, model: 'Y', idValues: {'Serial No.': '12'});
      expect(findDuplicateId(tiny, [tiny2]), isNull);
    });
  });

  group('customer search', () {
    const row = InstCustomerRow(
      id: 1,
      name: 'Muhammad Ali',
      phone: '0300-1234567',
      profile: CustomerProfile(customerId: 1, fatherName: 'Aslam', cnic: '35202-1234567-1', address: 'Bhikhi'),
    );

    test('name, father, address, phone, CNIC', () {
      expect(row.matches('ali'), isTrue);
      expect(row.matches('ali aslam'), isTrue);
      expect(row.matches('bhikhi'), isTrue);
      expect(row.matches('1234567'), isTrue);
      expect(row.matches('3520212345671'), isTrue);
      expect(row.matches('35202-1234'), isTrue);
      expect(row.matches('usman'), isFalse);
      expect(row.matches('12'), isFalse);
    });
  });
}
