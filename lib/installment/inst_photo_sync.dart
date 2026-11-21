import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../services/party_photo_store.dart';
import '../sync/sync_queue_dao.dart';
import '../sync/sync_queue_helper.dart';
import '../sync/sync_types.dart';
import 'inst_sync_names.dart';
import 'kyc_photo_store.dart';

/// Hanna Installment — tasveeron ka sync, Firebase Storage ke BAGHAIR (Spark free plan par Storage nahi).
///
/// Har tasveer ek Firestore document (`inst_photos`) mein base64 JPEG: customer ka chehra (owner `c`, kind `face`),
/// customer / guarantor ki CNIC aage-peeche, guarantor ki tasveer, cheque / stamp. Tasveerein pehle hi chhoti li jati
/// hain (chehra 800-900px, CNIC 1100px q75 ≈ 100-250 KB). Document ki had 1 MB hai; [maxBytes] (600 KB) se bari file
/// upload nahi hoti (us ka ek audit-type log `skipped` mein).
///
/// Doc id: `inst_photo:<owner>|<ownerServerId>|<kind>` — har device par ek hi (kisi aur ki copy nahi banti).
/// Owner ki pehchan uski serverId se (customer: customers.serverId, guarantor: inst_guarantors.serverId).
/// Pull par [applyInstallmentPhotos] file likhta hai (saveBytes — dobara upload nahi hoti).
class InstPhotoSync {
  InstPhotoSync._();

  /// Firestore doc 1 MB tak; base64 ~1.37x. Is se bari JPEG nahi bhejte.
  static const maxBytes = 600 * 1024;

  /// Jo tasveerein had se bari hone ki wajah se nahi gayin (screen par batane ke liye).
  static final List<String> skipped = [];

  static String docId(String owner, String ownerSid, String kind) => 'inst_photo:$owner|$ownerSid|$kind';

  /// main() mein: dono stores ki local tabdeeli -> queue; "Force full push" ke baad sab tasveerein bhi.
  static void install() {
    SyncQueueHelper.afterResync = enqueueAll;
    PartyPhotoStore.onLocalChange = (customer, id, path) {
      if (customer) _safe(() => queue('c', id, 'face', path));
    };
    KycPhotoStore.onLocalChange = (owner, id, kind, path) => _safe(() => queue(owner, id, kind, path));
  }

  static void _safe(Future<void> Function() f) {
    f().catchError((_) {});
  }

  static Future<String?> _ownerSid(DatabaseExecutor ex, String owner, int id) async {
    final table = owner == 'g' ? 'inst_guarantors' : (owner == 'p' ? 'inst_plans' : 'customers');
    final r = await ex.query(table, columns: ['serverId'], where: 'id = ?', whereArgs: [id], limit: 1);
    final sid = r.isEmpty ? null : r.first['serverId'];
    return sid is String && sid.trim().isNotEmpty ? sid : null;
  }

  /// Ek tasveer upload (path) ya cloud se hatao (path null). Owner abhi sync nahi hua (serverId nahi) to kuch nahi —
  /// "Force full push" baad mein bhej deta hai.
  static Future<void> queue(String owner, int id, String kind, String? path) async {
    final db = await AppDatabase.instance.database;
    final sid = await _ownerSid(db, owner, id);
    if (sid == null) return;
    final eid = docId(owner, sid, kind);
    if (path == null) {
      await SyncQueueHelper.enqueueDelete(db, instPhotoType, eid);
      return;
    }
    final f = File(path);
    if (!await f.exists()) return;
    final bytes = await f.readAsBytes();
    if (bytes.length > maxBytes) {
      skipped.add('$owner/$id/$kind (${bytes.length ~/ 1024} KB)');
      return;
    }
    await db.transaction((txn) async {
      // Isi tasveer ki purani, abhi tak na gayi upload hata do (queue mein do bari copies na rahein).
      await txn.delete('sync_queue',
          where: 'syncedAt IS NULL AND entityType = ? AND entityId = ?', whereArgs: [instPhotoType, eid]);
      await SyncQueueHelper.enqueue(txn, instPhotoType, eid, 'upsert', {
        'serverId': eid,
        'owner': owner,
        'ownerServerId': sid,
        'kind': kind,
        'data': base64Encode(bytes),
        'size': bytes.length,
        'createdAt': SyncQueueHelper.nowMs(),
        'updatedAt': SyncQueueHelper.nowMs(),
        'branchId': SyncQueueHelper.branchId(),
        '_deleted': false,
      });
    });
  }

  /// "Force full push": is device ki sab tasveerein dobara queue.
  static Future<void> enqueueAll() async {
    final party = PartyPhotoStore.instance;
    await party.ensureLoaded();
    final db = await AppDatabase.instance.database;
    for (final r in await db.query('customers', columns: ['id'])) {
      final id = (r['id'] as num).toInt();
      final path = party.pathFor(true, id);
      if (path != null) await queue('c', id, 'face', path);
    }
    final kyc = KycPhotoStore.instance;
    await kyc.ensureLoaded();
    for (final (owner, id, kind, path) in kyc.entries()) {
      await queue(owner, id, kind, path);
    }
  }
}

/// Pull: tasveeron ke documents -> files. `applyInstallmentChanges` ke baad (guarantors pehle aa chuke).
Future<void> applyInstallmentPhotos(DatabaseExecutor db, List<SyncDoc> docs) async {
  if (docs.isEmpty) return;
  final q = SyncQueueDao(db);
  for (final d in docs) {
    try {
      final sid = d['serverId'];
      final owner = d['owner'];
      final ownerSid = d['ownerServerId'];
      final kind = d['kind'];
      if (sid is! String || owner is! String || ownerSid is! String || kind is! String) continue;
      if (owner != 'c' && owner != 'g' && owner != 'p') continue; // p = plan ke dastakhat
      if (!RegExp(r'^[A-Za-z]{1,12}$').hasMatch(kind)) continue;
      if (await q.pendingCountForEntity(instPhotoType, sid) > 0) continue; // is device ki nayi tasveer abhi jani hai
      final table = owner == 'g' ? 'inst_guarantors' : (owner == 'p' ? 'inst_plans' : 'customers');
      final r = await db.query(table, columns: ['id'], where: 'serverId = ?', whereArgs: [ownerSid], limit: 1);
      if (r.isEmpty) continue;
      final id = (r.first['id'] as num).toInt();
      final deleted = d['_deleted'] == true;
      // Wahi tasveer pehle se hai (har pull overlap mein dobara aati hai, aur apni bheji hui bhi wapas aati hai).
      final size = d['size'];
      if (!deleted && size is num) {
        final have = owner == 'c' && kind == 'face'
            ? (await PartyPhotoStore.instance.ensureLoaded().then((_) => PartyPhotoStore.instance.pathFor(true, id)))
            : (await KycPhotoStore.instance.ensureLoaded().then((_) => KycPhotoStore.instance.pathFor(owner, id, kind)));
        if (have != null && await File(have).exists() && await File(have).length() == size.toInt()) continue;
      }
      if (owner == 'c' && kind == 'face') {
        if (deleted) {
          await PartyPhotoStore.instance.removeQuiet(customer: true, id: id);
        } else if (d['data'] is String) {
          await PartyPhotoStore.instance.saveBytes(base64Decode(d['data'] as String), customer: true, id: id);
        }
        continue;
      }
      if (deleted) {
        await KycPhotoStore.instance.removeQuiet(owner: owner, id: id, kind: kind);
      } else if (d['data'] is String) {
        await KycPhotoStore.instance.saveBytes(base64Decode(d['data'] as String), owner: owner, id: id, kind: kind);
      }
    } catch (_) {
      // Ek kharab tasveer baqi sync na roke.
    }
  }
}
