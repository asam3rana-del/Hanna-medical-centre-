import 'package:flutter_test/flutter_test.dart';
import 'package:hanna_installment/license/license_core.dart';
import 'package:hanna_installment/license/license_keys.dart';
import 'package:hanna_installment/license/license_service.dart';

/// Test vectors tools/license_tool.py se, ek TEST key jodi se (asal private key se sign ki hui koi key yahan nahi).
const testPub = '901790ceccae5ba1ceb99aec0d089428d215e2808ea71842836ea2229f024f6b';
const device = 'ABCD-EFGH-JKMN-PQRS';
const trialKey = 'HI1-AEAQA-RBSCT-DUVGG-XYIZA-IFYEE-UAAAA-ABEMQ-C6MQX-D7XZ6-EYQTS-AJXPS-T2WK7-OR3JG-W26BF-WSKTG-NU4MA-RXAH6-5YLG7-YWNCN-KUIAT-I2CWH-HATLO-EEHCI-VDRT4-GT432-FVR2P-VEGCI';
const annualKey = 'HI1-AEBAA-RBSCT-DUVGG-XYIZA-IFYFS-UAAAA-ACB27-OYBGD-WYIA7-PW4ES-D66YM-5ETRK-3JFI7-VWBPE-MERPO-B7GPC-23JQD-NZTSY-ZLYUT-YPBRS-2PMAY-Y24Q6-KOUMV-M7LOK-37H5K-CZOE2-YM6BY';
const otherDeviceKey = 'HI1-AEBM4-444MM-ML333-3LLLA-IFYFS-UAAAA-AD4Z6-FSV4N-VPTSX-CORTP-TZ5HH-3D2BJ-3RHYO-BPQKI-ZMSOM-SGKMU-7UWMT-NTM6I-OQRC6-EUVZ3-GZ6OE-R4SG6-RXPD4-2QYPY-6TVAJ-5KYMC-4T6BI';
const wrongSignerKey = 'HI1-AEBAA-RBSCT-DUVGG-XYIZA-IFYFS-UAAAA-AENQE-ZIM5Y-3VIWW-XS7TJ-JAZMQ-XVLXG-OUCEC-AU4RQ-LTBQQ-GPBJQ-IUCHS-GSEA5-PXCFO-BC63F-T4Q6O-MFVMS-4UUU2-7PWZA-PX62O-PLPM7-U5YCY';

DateTime d(int y, int m, int day) => DateTime(y, m, day, 12);

void main() {
  group('format', () {
    test('base32 round trip and device code formatting', () {
      final bytes = [for (var i = 0; i < 10; i++) i * 25];
      expect(base32Decode(base32Encode(bytes)), bytes);
      expect(base32Encode(bytes).length, 16);
      expect(formatDeviceCode('abcdefghjkmnpqrs'), device);
      expect(base32Decode('AB1'), isNull);
    });

    test('parse annual key (python tool ke saath ek jaisa)', () {
      final i = parseLicenseKey(annualKey)!;
      expect(i.type, licenseTypeAnnual);
      expect(formatDeviceCode(i.deviceCode), device);
      expect(i.issued, DateTime.utc(2026, 11, 13));
      expect(i.expiry, DateTime.utc(2027, 11, 30));
      expect(i.serial, 2);
      expect(i.signature.length, 64);
    });

    test('typing mistakes: lowercase, spaces, 0/O 1/I tolerated; garbage rejected', () {
      final messy = annualKey.toLowerCase().replaceAll('-', ' ');
      expect(parseLicenseKey(messy)?.serial, 2);
      expect(parseLicenseKey('HI1-ABCDE'), isNull);
      expect(parseLicenseKey(''), isNull);
      expect(parseLicenseKey(annualKey.substring(0, annualKey.length - 6)), isNull);
    });
  });

  group('signature', () {
    test('valid keys verify with the right public key', () async {
      expect(await verifyLicenseSignature(parseLicenseKey(trialKey)!, testPub), isTrue);
      expect(await verifyLicenseSignature(parseLicenseKey(annualKey)!, testPub), isTrue);
    });

    test('forged / edited keys fail', () async {
      // doosri private key se bani
      expect(await verifyLicenseSignature(parseLicenseKey(wrongSignerKey)!, testPub), isFalse);
      // asal app ki public key test key ko nahi maanti
      expect(await verifyLicenseSignature(parseLicenseKey(annualKey)!, LicenseKeys.publicKeyHex), isFalse);
      // ek harf badla (expiry badhane ki koshish)
      final body = normalizeLicenseText(annualKey);
      final i = body.length ~/ 5;
      final flipped = body.substring(0, i) + (body[i] == 'A' ? 'B' : 'A') + body.substring(i + 1);
      final info = parseLicenseKey(flipped);
      expect(info == null || !(await verifyLicenseSignature(info, testPub)), isTrue);
    });

    test('production public key is a 32-byte hex', () {
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(LicenseKeys.publicKeyHex), isTrue);
      expect(LicenseKeys.publicKeyHex, isNot(testPub));
    });
  });

  group('evaluate', () {
    final annual = parseLicenseKey(annualKey)!;
    LicenseStatus ev(DateTime today, {DateTime? seen, String dev = device, bool sig = true, Set<int> revoked = const {}}) =>
        evaluateLicense(info: annual, signatureOk: sig, deviceCode: dev, today: today, lastSeen: seen, revoked: revoked);

    test('active, ending soon, last day, expired', () {
      expect(ev(d(2027, 1, 1)), LicenseStatus.active);
      expect(ev(d(2027, 11, 20)), LicenseStatus.expiringSoon);
      expect(annual.daysLeft(d(2027, 11, 30)), 1);
      expect(ev(d(2027, 11, 30)), LicenseStatus.expiringSoon); // aakhri din bhi chalti hai
      expect(ev(d(2027, 12, 1)), LicenseStatus.expired);
      expect(ev(d(2027, 12, 1)).writable, isFalse);
      expect(ev(d(2027, 12, 1)).blocksApp, isFalse); // data dekh sakte hain
    });

    test('wrong device, bad signature, revoked, missing', () {
      expect(ev(d(2027, 1, 1), dev: 'ZZZZ-YYYY-XXXX-WWWW'), LicenseStatus.wrongDevice);
      expect(ev(d(2027, 1, 1), sig: false), LicenseStatus.invalid);
      expect(ev(d(2027, 1, 1), revoked: {2}), LicenseStatus.revoked);
      expect(evaluateLicense(info: null, signatureOk: false, deviceCode: device, today: d(2027, 1, 1)), LicenseStatus.missing);
      expect(LicenseStatus.wrongDevice.blocksApp, isTrue);
    });

    test('clock turned back: before last seen, or before the key was issued', () {
      expect(ev(d(2027, 3, 1), seen: d(2027, 6, 1)), LicenseStatus.clockBack);
      expect(ev(d(2027, 5, 31), seen: d(2027, 6, 1)), LicenseStatus.active); // 1 din ki gunjaish (timezone)
      expect(ev(d(2026, 1, 1)), LicenseStatus.clockBack); // key 13 Nov 2026 ko bani
      expect(LicenseStatus.clockBack.writable, isFalse);
    });

    test('15-day trial', () {
      final t = parseLicenseKey(trialKey)!;
      expect(t.isTrial, isTrue);
      expect(t.daysLeft(d(2026, 11, 13)), 15);
      expect(evaluateLicense(info: t, signatureOk: true, deviceCode: device, today: d(2026, 11, 28)), LicenseStatus.expired);
    });
  });

  group('service (memory store)', () {
    setUp(() {
      LicenseService.useMemoryStore = true;
      LicenseService.publicKeyOverride = testPub;
      LicenseService.instance.resetForTest();
    });

    test('device code is created once and stays', () async {
      final a = await LicenseService.instance.deviceCode();
      expect(a.length, 16);
      expect(await LicenseService.instance.deviceCode(), a);
    });

    test('no key -> missing; key of another device is refused and not saved', () async {
      expect(await LicenseService.instance.check(now: d(2027, 1, 1)), LicenseStatus.missing);
      expect(await LicenseService.instance.activate(annualKey, now: d(2027, 1, 1)), LicenseStatus.wrongDevice);
      expect(await LicenseService.instance.storedKey(), isNull);
    });
  });
}
