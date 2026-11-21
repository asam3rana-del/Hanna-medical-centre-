import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Hanna Installment license — key ka format aur faisla (PURE; test/license_test.dart).
///
/// Key = "HI1-" + Base32( payload[20] + Ed25519 dastakhat[64] ), 5-5 harf ke group.
/// payload: [1 version=1][1 type: 1 trial, 2 annual][10 device code][2 issued day][2 expiry day][4 serial]
/// day = 2024-01-01 se din, big-endian. tools/license_tool.py aur tools/license_generator.html bilkul yahi banate hain.
///
/// Hifazat:
///  * Dastakhat sirf Hanna Solutions ki private key se ban sakte hain; app ke andar sirf public key — app khol kar bhi
///    nayi key nahi ban sakti, aur key ka ek harf bhi badlo to dastakhat ghalat.
///  * Key device code se bandhi: ek phone ki key doosre par "wrong device".
///  * Tareekh peeche ki gayi (aakhri dekhi tareekh se 1 din se zyada, ya key ke issue din se pehle) -> clockBack.
///  * Wapas li gayi serial -> revoked.

const licenseKeyPrefix = 'HI1';
const licenseTypeTrial = 1;
const licenseTypeAnnual = 2;

/// Expiry se itne din pehle "jaldi khatam" warning.
const licenseWarnDays = 15;

final DateTime licenseEpoch = DateTime.utc(2024, 1, 1);

const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String base32Encode(List<int> data) {
  final out = StringBuffer();
  var bits = 0, val = 0;
  for (final byte in data) {
    val = ((val << 8) | (byte & 0xFF)) & 0xFFFF;
    bits += 8;
    while (bits >= 5) {
      out.write(_b32[(val >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_b32[(val << (5 - bits)) & 31]);
  return out.toString();
}

/// Ghalat harf => null.
Uint8List? base32Decode(String text) {
  final out = <int>[];
  var bits = 0, val = 0;
  for (final ch in text.split('')) {
    final v = _b32.indexOf(ch);
    if (v < 0) return null;
    val = ((val << 5) | v) & 0xFFFF;
    bits += 5;
    if (bits >= 8) {
      out.add((val >> (bits - 8)) & 0xFF);
      bits -= 8;
    }
  }
  return Uint8List.fromList(out);
}

/// Bara harf, sirf harf/hindse; aam ghaltiyan: 0->O, 1->I, 8->B (Base32 mein yeh hindse nahi).
String normalizeLicenseText(String text) => text
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z0-9]'), '')
    .replaceAll('0', 'O')
    .replaceAll('1', 'I')
    .replaceAll('8', 'B');

/// 16 harf -> "ABCD-EFGH-JKMN-PQRS".
String formatDeviceCode(String code) {
  final t = normalizeLicenseText(code);
  return [for (var i = 0; i < t.length; i += 4) t.substring(i, i + 4 > t.length ? t.length : i + 4)].join('-');
}

DateTime _dayToDate(int d) => licenseEpoch.add(Duration(days: d));
int dateToLicenseDay(DateTime local) => DateTime.utc(local.year, local.month, local.day).difference(licenseEpoch).inDays;

class LicenseInfo {
  final int type;

  /// 16 harf (Base32 of 10 bytes), bina dash.
  final String deviceCode;

  /// Din (UTC midnight) — sirf tareekh maani hai.
  final DateTime issued;

  /// Is din ke aakhir tak chalti hai.
  final DateTime expiry;
  final int serial;
  final Uint8List payload;
  final Uint8List signature;

  const LicenseInfo({
    required this.type,
    required this.deviceCode,
    required this.issued,
    required this.expiry,
    required this.serial,
    required this.payload,
    required this.signature,
  });

  bool get isTrial => type == licenseTypeTrial;
  String get typeName => isTrial ? 'Trial' : 'Annual';

  /// [today] (local) ke hisaab se kitne din baqi (aaj samet). 0 = aaj aakhri din, minus = khatam.
  int daysLeft(DateTime today) => dateToLicenseDay(expiry) - dateToLicenseDay(today) + 1;
}

/// Sirf format padhta hai (dastakhat [verifyLicenseSignature] mein). Ghalat => null.
LicenseInfo? parseLicenseKey(String text) {
  final t = normalizeLicenseText(text);
  if (!t.startsWith('HII')) return null; // "HI1" -> normalize -> "HII"
  final raw = base32Decode(t.substring(3));
  if (raw == null || raw.length != 84) return null;
  final payload = Uint8List.sublistView(raw, 0, 20);
  if (payload[0] != 1) return null;
  final type = payload[1];
  if (type != licenseTypeTrial && type != licenseTypeAnnual) return null;
  final bd = ByteData.sublistView(payload);
  final issued = bd.getUint16(12);
  final expiry = bd.getUint16(14);
  if (expiry < issued) return null;
  return LicenseInfo(
    type: type,
    deviceCode: base32Encode(payload.sublist(2, 12)),
    issued: _dayToDate(issued),
    expiry: _dayToDate(expiry),
    serial: bd.getUint32(16),
    payload: Uint8List.fromList(payload),
    signature: Uint8List.fromList(raw.sublist(20)),
  );
}

List<int> _hex(String h) => [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];

/// Ed25519 dastakhat [publicKeyHex] (32 byte hex) se.
Future<bool> verifyLicenseSignature(LicenseInfo info, String publicKeyHex) async {
  try {
    final pub = SimplePublicKey(_hex(publicKeyHex), type: KeyPairType.ed25519);
    return await Ed25519().verify(info.payload, signature: Signature(info.signature, publicKey: pub));
  } catch (_) {
    return false;
  }
}

enum LicenseStatus {
  /// Abhi koi key nahi dali.
  missing,

  /// Key ka format / dastakhat ghalat.
  invalid,

  /// Key kisi aur device ki.
  wrongDevice,

  /// Serial wapas li gayi.
  revoked,

  /// Phone ki tareekh peeche ki gayi.
  clockBack,
  active,
  expiringSoon,
  expired,
}

extension LicenseStatusX on LicenseStatus {
  /// Naya data likh sakte hain (customer, plan, wasooli...). Baqi halaton mein sirf dekhna + backup.
  bool get writable => this == LicenseStatus.active || this == LicenseStatus.expiringSoon;

  /// App bilkul nahi khulti (License screen) — kabhi sahi key lagi hi nahi.
  bool get blocksApp => this == LicenseStatus.missing || this == LicenseStatus.invalid || this == LicenseStatus.wrongDevice;
}

/// Faisla (PURE). [today] = phone ki tareekh; [lastSeen] = is device par ab tak ki sab se aagay wali dekhi tareekh.
LicenseStatus evaluateLicense({
  required LicenseInfo? info,
  required bool signatureOk,
  required String deviceCode,
  required DateTime today,
  DateTime? lastSeen,
  Set<int> revoked = const {},
}) {
  if (info == null) return LicenseStatus.missing;
  if (!signatureOk) return LicenseStatus.invalid;
  if (normalizeLicenseText(info.deviceCode) != normalizeLicenseText(deviceCode)) return LicenseStatus.wrongDevice;
  if (revoked.contains(info.serial)) return LicenseStatus.revoked;
  final todayDay = dateToLicenseDay(today);
  if (lastSeen != null && todayDay < dateToLicenseDay(lastSeen) - 1) return LicenseStatus.clockBack;
  if (todayDay < dateToLicenseDay(info.issued) - 1) return LicenseStatus.clockBack; // key "kal" bani, phone "pichhle saal"
  final left = info.daysLeft(today);
  if (left <= 0) return LicenseStatus.expired;
  if (left <= licenseWarnDays) return LicenseStatus.expiringSoon;
  return LicenseStatus.active;
}
