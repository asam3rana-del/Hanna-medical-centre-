import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/installment/inst_terms.dart';

void main() {
  test('terms: one per line, blanks dropped', () {
    expect(InstTerms.lines('1. a\n\n  2. b  \n'), ['1. a', '2. b']);
    expect(InstTerms.lines(''), isEmpty);
    expect(InstTerms.lines(InstTerms.defaultUrdu).length, 5);
    expect(InstTerms.lines(InstTerms.defaultEnglish).length, 5);
  });
}
