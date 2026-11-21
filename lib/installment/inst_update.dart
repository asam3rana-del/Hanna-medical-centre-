import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../utils/loc.dart';

/// App ke andar "naya update aaya hai" (Play Store ke baghair).
///
/// Hanna Solutions ek public file rakhta hai ([AppInfo.updateUrl], tafseel docs/UPDATES.md):
/// ```json
/// {
///   "android": {"version": "1.0.0", "build": 31, "url": "https://.../app-release.apk", "notes": "Kya naya hai"},
///   "windows": {"version": "1.0.0", "build": 31, "url": "https://.../Hanna-Installment-windows.zip", "notes": ""},
///   "min_build": 0
/// }
/// ```
/// App ka apna build ([AppInfo.build], CI ka run number) is se chhota ho to Home par dialog; Download = browser mein
/// link (Android khud install poochta hai — purani app ke upar, data aur license wahi). `min_build` se chhota build ho
/// to dialog band nahi hota (zaroori update). Har 6 ghante mein ek dafa check; internet na ho to chup.
/// Hifazat: Android sirf usi signing key wali APK ko update maanta hai — koi aur link de bhi de to install nahi hogi.
class UpdateInfo {
  final String version;
  final int build;
  final String url;
  final String notes;

  /// Is build se purani app ko update lazmi.
  final int minBuild;
  const UpdateInfo({required this.version, required this.build, required this.url, this.notes = '', this.minBuild = 0});

  bool newerThan(int current) => build > current;
  bool requiredFor(int current) => current < minBuild && build > current;
}

/// PURE (test hota hai). [platform]: 'android' / 'windows' / 'ios'. Ghalat / adhuri file = null.
UpdateInfo? parseUpdateInfo(String body, String platform) {
  try {
    final j = jsonDecode(body);
    if (j is! Map) return null;
    final m = j[platform];
    if (m is! Map) return null;
    final build = m['build'];
    final url = m['url'];
    if (build is! num || url is! String || !url.startsWith('https://')) return null;
    final minBuild = m['min_build'] ?? j['min_build'];
    return UpdateInfo(
      version: '${m['version'] ?? ''}',
      build: build.toInt(),
      url: url,
      notes: '${m['notes'] ?? ''}',
      minBuild: minBuild is num ? minBuild.toInt() : 0,
    );
  } catch (_) {
    return null;
  }
}

class InstUpdate {
  InstUpdate._();

  static const _kLast = 'inst_update_last_check';
  static const _every = Duration(hours: 6);
  static bool _showing = false;

  /// CI build number (local / purani build par 0).
  static int get currentBuild => int.tryParse(AppInfo.build) ?? 0;

  static String? get _platform {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    return null;
  }

  static Future<UpdateInfo?> fetch() async {
    final plat = _platform;
    if (plat == null || AppInfo.updateUrl.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(AppInfo.updateUrl).replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch ~/ 60000}'});
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      if (body.length > 20000) return null;
      return parseUpdateInfo(body, plat);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Home khulne par: 6 ghante mein ek dafa, chup chaap. Local build (0) par kuch nahi.
  static Future<void> checkOnStart(BuildContext context) async {
    final cur = currentBuild;
    if (cur <= 0 || _showing) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_kLast) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _every.inMilliseconds && now >= last) return;
      final info = await fetch();
      if (info == null) return; // internet nahi: agli dafa phir
      await prefs.setInt(_kLast, now);
      if (!info.newerThan(cur) || !context.mounted) return;
      await _dialog(context, info, required: info.requiredFor(cur));
    } catch (_) {
      // update check kabhi app na roke
    }
  }

  /// Shop tools > "Update check karein".
  static Future<void> checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(Loc.t('Checking for update...', 'اپڈیٹ دیکھ رہے ہیں...'))));
    final info = await fetch();
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    final cur = currentBuild;
    if (info == null) {
      messenger.showSnackBar(
          SnackBar(content: Text(Loc.t('Could not check (internet?). Try again later.', 'چیک نہیں ہو سکا (انٹرنیٹ؟)۔ بعد میں دوبارہ کوشش کریں۔'))));
      return;
    }
    if (!info.newerThan(cur)) {
      messenger.showSnackBar(SnackBar(
          content: Text(Loc.t('You have the latest version (build $cur).', 'آپ کے پاس نیا ورژن ہے (build $cur)۔'))));
      return;
    }
    await _dialog(context, info, required: info.requiredFor(cur));
  }

  static Future<void> _dialog(BuildContext context, UpdateInfo info, {required bool required}) async {
    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !required,
        builder: (ctx) => PopScope(
          canPop: !required,
          child: AlertDialog(
            icon: const Icon(Icons.system_update, size: 36),
            title: Text(required
                ? Loc.t('Update required', 'اپڈیٹ ضروری ہے')
                : Loc.t('New update available', 'نیا اپڈیٹ آ گیا ہے')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${AppInfo.appName} ${info.version} (build ${info.build})', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (info.notes.trim().isNotEmpty) ...[const SizedBox(height: 8), Text(info.notes.trim())],
                const SizedBox(height: 10),
                Text(
                  Loc.t('Install it over the current app. Do NOT uninstall — your data and license stay.',
                      'موجودہ ایپ کے اوپر انسٹال کریں۔ ان انسٹال نہ کریں — ڈیٹا اور لائسنس وہی رہیں گے۔'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ]),
            ),
            actions: [
              if (!required) TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Loc.t('Later', 'بعد میں'))),
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text(Loc.t('Download', 'ڈاؤن لوڈ')),
                onPressed: () async {
                  final ok = await launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication);
                  if (!ok && ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(info.url)));
                  }
                  if (!required && ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      );
    } finally {
      _showing = false;
    }
  }
}
