import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Qist ke kaghzat ki tasveerein: CNIC aage / peeche, guarantor ki tasveer, cheque / stamp paper.
///
/// [PartyPhotoStore] jaisa: sirf IS device par (`kyc_photos/` folder), DB / sync mein nahi.
/// File ka naam: `<owner>_<id>_<kind>_<time>.jpg` — owner `c` (customer) ya `g` (guarantor).
/// Customer ki apni chehre wali tasveer [PartyPhotoStore] mein hi rehti hai (POS ke avatar bhi wahi dikhate hain).
class KycPhotoStore {
  KycPhotoStore._();
  static final KycPhotoStore instance = KycPhotoStore._();

  static const cnicFront = 'cnicF';
  static const cnicBack = 'cnicB';
  static const photo = 'photo';
  static const document = 'doc';


  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Is device par tasveer li / hatai gayi (path null = hatai) — InstPhotoSync upload karta hai.
  /// Sync se aayi tasveer ([saveBytes] / [removeQuiet]) yeh nahi bulati.
  static void Function(String owner, int id, String kind, String? path)? onLocalChange;

  /// Sab tasveerein (owner, id, kind, path) — "Force full push" ke liye.
  List<(String, int, String, String)> entries() => [
        for (final e in _index.entries)
          if (_keyRe.firstMatch(e.key) case final m?) (m.group(1)!, int.parse(m.group(2)!), m.group(3)!, e.value)
      ];
  static final _keyRe = RegExp(r'^([cg])_(\d+)_([A-Za-z]+)$');

  final Map<String, String> _index = {};
  Future<void>? _loading;

  static final _nameRe = RegExp(r'^([cgp])_(\d+)_([A-Za-z]+)_(\d+)\.jpg$'); // p = plan (dastakhat, Step 32)

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'kyc_photos'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  String _key(String owner, int id, String kind) => '${owner}_${id}_$kind';

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final best = <String, (int, String)>{};
      for (final e in (await _dir()).listSync()) {
        if (e is! File) continue;
        final m = _nameRe.firstMatch(p.basename(e.path));
        if (m == null) continue;
        final k = _key(m.group(1)!, int.parse(m.group(2)!), m.group(3)!);
        final ts = int.parse(m.group(4)!);
        if (!best.containsKey(k) || ts > best[k]!.$1) best[k] = (ts, e.path);
      }
      _index
        ..clear()
        ..addEntries(best.entries.map((e) => MapEntry(e.key, e.value.$2)));
    } catch (_) {}
  }

  /// [ensureLoaded] ke baad. Tasveer nahi to null.
  String? pathFor(String owner, int id, String kind) => _index[_key(owner, id, kind)];

  /// Desktop (Windows) par camera nahi — sirf file / gallery.
  static bool get cameraAvailable =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<String?> pick(ImageSource source, {required String owner, required int id, required String kind}) async {
    final picker = ImagePicker();
    // CNIC parhne layak rahe aur sync ke liye chhoti: 1100px, quality 75 (~150-250 KB).
    XFile? x = await picker.pickImage(source: source, maxWidth: 1100, maxHeight: 1100, imageQuality: 75);
    if (x == null && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final lost = await picker.retrieveLostData();
        if (!lost.isEmpty && lost.file != null) x = lost.file;
      } catch (_) {}
    }
    if (x == null) return null;
    await ensureLoaded();
    final dir = await _dir();
    final dest = File(p.join(dir.path, '${owner}_${id}_${kind}_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    await File(x.path).copy(dest.path);
    await _deleteOld(owner, id, kind, keep: dest.path);
    _index[_key(owner, id, kind)] = dest.path;
    changes.value++;
    onLocalChange?.call(owner, id, kind, dest.path);
    return dest.path;
  }

  /// Pehle se li hui tasveer (form mein save se pehle) ko record ke naam se rakhta hai.
  Future<String?> saveFrom(String srcPath, {required String owner, required int id, required String kind}) async {
    final src = File(srcPath);
    if (!await src.exists()) return null;
    await ensureLoaded();
    final dir = await _dir();
    final dest = File(p.join(dir.path, '${owner}_${id}_${kind}_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    await src.copy(dest.path);
    await _deleteOld(owner, id, kind, keep: dest.path);
    _index[_key(owner, id, kind)] = dest.path;
    changes.value++;
    onLocalChange?.call(owner, id, kind, dest.path);
    return dest.path;
  }

  /// Sirf tasveer chunwata hai (save nahi) — form ke andar preview ke liye. Cancel => null.
  static Future<String?> pickTemp(ImageSource source, {int maxSide = 1100}) async {
    final picker = ImagePicker();
    XFile? x = await picker.pickImage(source: source, maxWidth: maxSide.toDouble(), maxHeight: maxSide.toDouble(), imageQuality: 75);
    if (x == null && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final lost = await picker.retrieveLostData();
        if (!lost.isEmpty && lost.file != null) x = lost.file;
      } catch (_) {}
    }
    return x?.path;
  }

  Future<void> remove({required String owner, required int id, required String kind}) async {
    await removeQuiet(owner: owner, id: id, kind: kind);
    onLocalChange?.call(owner, id, kind, null);
  }

  /// Sync se aayi tasveer (bytes) — upload callback nahi bulata.
  Future<void> saveBytes(List<int> bytes, {required String owner, required int id, required String kind}) async {
    await ensureLoaded();
    final dir = await _dir();
    final dest = File(p.join(dir.path, '${owner}_${id}_${kind}_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    await dest.writeAsBytes(bytes, flush: true);
    await _deleteOld(owner, id, kind, keep: dest.path);
    _index[_key(owner, id, kind)] = dest.path;
    changes.value++;
  }

  Future<void> removeQuiet({required String owner, required int id, required String kind}) async {
    await ensureLoaded();
    await _deleteOld(owner, id, kind);
    _index.remove(_key(owner, id, kind));
    changes.value++;
  }

  /// Guarantor delete hone par us ki saari tasveerein bhi.
  Future<void> removeAll({required String owner, required int id}) async {
    await ensureLoaded();
    final kinds = [
      for (final k in _index.keys)
        if (k.startsWith('${owner}_${id}_')) k.substring('${owner}_${id}_'.length)
    ];
    try {
      final prefix = '${owner}_${id}_';
      for (final e in (await _dir()).listSync()) {
        if (e is File && p.basename(e.path).startsWith(prefix)) await e.delete();
      }
    } catch (_) {}
    _index.removeWhere((k, _) => k.startsWith('${owner}_${id}_'));
    changes.value++;
    for (final k in kinds) {
      onLocalChange?.call(owner, id, k, null);
    }
  }

  Future<void> _deleteOld(String owner, int id, String kind, {String? keep}) async {
    try {
      final prefix = '${owner}_${id}_${kind}_';
      for (final e in (await _dir()).listSync()) {
        if (e is File && p.basename(e.path).startsWith(prefix) && e.path != keep) await e.delete();
      }
    } catch (_) {}
  }
}
