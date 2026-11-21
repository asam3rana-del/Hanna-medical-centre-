import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/services/contact_picker.dart';

void main() {
  test('cleanPhoneNumber keeps digits and + only (Kotlin regex)', () {
    expect(cleanPhoneNumber('+92 300-123 4567'), '+923001234567');
    expect(cleanPhoneNumber('(0300) 1234567'), '03001234567');
    expect(cleanPhoneNumber(''), '');
  });
}
