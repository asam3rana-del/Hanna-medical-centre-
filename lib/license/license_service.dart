import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/demo_mode.dart';
import 'license_core.dart';
import 'license_keys.dart';

/// Is device ka license: device code, key, tareekh ki hifazat, aur "likh sakte hain?" ka faisla.
///
/// * Device code: pehli dafa 10 random byte -> Base32 (16 harf). Secure storage (Android Keystore / Windows DPAPI) +
///   SharedPreferences dono mein (ek na chale to doosra). Android backup band (allowBackup=false), is liye naye phone
///   par code nahi jata — ek key do phone par nahi chalti. App uninstall / data clear = naya code (nayi key chahiye).
/// * Key: secure storage + SharedPreferences (key khud raaz nahi — device se bandhi hai).
/// * Aakhri dekhi tareekh: dono jagah, bari wali maani jati hai; har check par aage barhti hai. Phone ki tareekh is se
///   1 din se zyada peeche ho to [LicenseStatus.clockBack] (app sirf dekhne ke liye).
/// * Demo mode (alag practice DB) license ke baghair chalta hai — Play reviewer / naye customer ke liye.
class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const _kDevice = 'hanna_lic_device_v1';
  static const _kKey = 'hanna_lic_key_v1';
  static const _kSeen = 'hanna_lic_seen_v1';

  // Wahi options jo backup password (lib/backup/backup_password_store.dart) ke hain. Pehle yahan default options the:
  // flutter_secure_storage 9 mein jab koi aur hissa encryptedSharedPreferences: true se chalta hai to plugin purani
  // (non-encrypted) entries ko EncryptedSharedPreferences mein le jata hai aur purani jagah se mita deta hai — phir
  // license ko apna device code nahi milta tha, har dafa naya banta tha ("This key is for another device").
  final _secure = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  /// Har check ke baad (banner / gate dobara banne ke liye).
  final ValueNotifier<LicenseStatus?> status = ValueNotifier<LicenseStatus?>(null);
  LicenseInfo? _info;
  String? _device;
  Future<LicenseStatus>? _checking;

  LicenseInfo? get info => _info;

  /// Test: secure storage ki jagah memory (plugin nahi hota).
  @visibleForTesting
  static bool useMemoryStore = false;

  /// Test: test wali public key (asal private key se sign ki hui koi key repo mein nahi rakhte).
  @visibleForTesting
  static String? publicKeyOverride;

  @visibleForTesting
  void resetForTest() {
    _mem.clear();
    _device = null;
    _info = null;
    _checking = null;
    status.value = null;
  }

  String get _pub => publicKeyOverride ?? LicenseKeys.publicKeyHex;
  static final Map<String, String> _mem = {};

  Future<String?> _read(String k) async {
    if (useMemoryStore) return _mem[k];
    String? v;
    try {
      v = await _secure.read(key: k);
    } catch (_) {}
    if (v != null && v.isNotEmpty) return v;
    try {
      return (await SharedPreferences.getInstance()).getString(k);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String k, String v, {bool prefsToo = true}) async {
    if (useMemoryStore) {
      _mem[k] = v;
      return;
    }
    var secureOk = false;
    try {
      await _secure.write(key: k, value: v);
      secureOk = true;
    } catch (_) {}
    // prefsToo = false ho to prefs sirf tab jab secure storage na chale.
    if (prefsToo || !secureOk) {
      try {
        await (await SharedPreferences.getInstance()).setString(k, v);
      } catch (_) {}
    }
  }

  /// Is device ka code (16 harf, bina dash).
  Future<String> deviceCode() async {
    if (_device != null) return _device!;
    var d = await _read(_kDevice);
    if (d == null || normalizeLicenseText(d).length != 16) {
      final r = Random.secure();
      d = base32Encode([for (var i = 0; i < 10; i++) r.nextInt(256)]);
    }
    // Hamesha dono jagah (secure + prefs): secure storage kabhi parh na sake to bhi wahi code mile. Android backup
    // band hai (tools/android_fix.sh: allowBackup="false"), is liye prefs doosre phone par nahi jate.
    await _write(_kDevice, d);
    return _device = normalizeLicenseText(d);
  }

  Future<String?> storedKey() => _read(_kKey);

  /// Status nikalo (ek waqt mein ek hi check).
  Future<LicenseStatus> check({DateTime? now}) => _checking ??= _check(now ?? DateTime.now()).whenComplete(() => _checking = null);

  Future<LicenseStatus> _check(DateTime now) async {
    final device = await deviceCode();
    final key = await storedKey();
    final seen = await _lastSeen();
    LicenseStatus st;
    LicenseInfo? info;
    if (key == null || key.trim().isEmpty) {
      st = LicenseStatus.missing;
    } else {
      info = parseLicenseKey(key);
      final sigOk = info != null && await verifyLicenseSignature(info, _pub);
      st = evaluateLicense(
          info: info, signatureOk: sigOk, deviceCode: device, today: now, lastSeen: seen, revoked: LicenseKeys.revokedSerials);
    }
    // Tareekh aage barhao — peeche wali kabhi nahi, aur license ki muddat se aage bhi nahi (ghalti se 2030 lag jaye
    // to theek karne par app band na ho).
    final withinLicense = info != null && dateToLicenseDay(now) <= dateToLicenseDay(info.expiry) + 1;
    if ((st.writable || st == LicenseStatus.expired) && withinLicense && (seen == null || now.isAfter(seen))) {
      await _write(_kSeen, '${now.millisecondsSinceEpoch}');
    }
    _info = (st == LicenseStatus.invalid || st == LicenseStatus.missing) ? null : info;
    status.value = st;
    return st;
  }

  Future<DateTime?> _lastSeen() async {
    int best = 0;
    for (final v in [
      if (!useMemoryStore) await _safeSecure(_kSeen),
      if (!useMemoryStore) await _safePrefs(_kSeen),
      if (useMemoryStore) _mem[_kSeen],
    ]) {
      final n = int.tryParse(v ?? '') ?? 0;
      if (n > best) best = n;
    }
    return best == 0 ? null : DateTime.fromMillisecondsSinceEpoch(best);
  }

  Future<String?> _safeSecure(String k) async {
    try {
      return await _secure.read(key: k);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _safePrefs(String k) async {
    try {
      return (await SharedPreferences.getInstance()).getString(k);
    } catch (_) {
      return null;
    }
  }

  /// Nayi key lagao. Sirf sahi (dastakhat + isi device + khatam nahi) key save hoti hai; warna wajah wapas.
  ///
  /// Nayi serial wali key "aakhri dekhi tareekh" ki pakar reset karti hai (developer ne aaj ki tareekh par di — phone ki
  /// tareekh us ke issue din se pehle ho hi nahi sakti). Wahi purani key dobara dalne se reset NAHI hota.
  Future<LicenseStatus> activate(String keyText, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final device = await deviceCode();
    final info = parseLicenseKey(keyText);
    if (info == null) return LicenseStatus.invalid;
    final sigOk = await verifyLicenseSignature(info, _pub);
    final old = parseLicenseKey(await storedKey() ?? '');
    final freshSerial = old == null || old.serial != info.serial;
    final st = evaluateLicense(
        info: info,
        signatureOk: sigOk,
        deviceCode: device,
        today: t,
        lastSeen: freshSerial ? null : await _lastSeen(),
        revoked: LicenseKeys.revokedSerials);
    if (!st.writable) return st;
    await _write(_kKey, keyText.trim());
    if (freshSerial) await _write(_kSeen, '${t.millisecondsSinceEpoch}', prefsToo: true);
    return check(now: t);
  }

  /// Likhne se pehle (repositories). Demo mode hamesha chalta hai.
  Future<void> requireWritable() async {
    if (DemoMode.enabled) return;
    final st = status.value ?? await check();
    if (!st.writable) throw ArgumentError(blockedMessage(st));
  }

  static String blockedMessage(LicenseStatus st) => switch (st) {
        LicenseStatus.expired => 'License khatam ho gaya — data dekh sakte hain aur backup le sakte hain. Naya kaam ke liye license renew karein.',
        LicenseStatus.clockBack => 'Phone ki tareekh / waqt ghalat (peeche) hai — Settings mein Automatic date & time on karein.',
        LicenseStatus.revoked => 'Ye license band kar diya gaya hai — Hanna Solutions se rabta karein.',
        _ => 'License nahi hai — License screen se key lagayein.',
      };
}
