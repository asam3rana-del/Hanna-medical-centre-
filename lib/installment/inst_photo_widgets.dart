import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'kyc_photo_store.dart';

/// Form ke andar ek tasveer ki jagah: pehle se saved ([savedPath]), nayi li hui ([newPath]) ya hatai hui ([removed]).
/// Save hone par form khud store mein likhta hai (record ki id tab pata hoti hai).
class PhotoSlot {
  final String? savedPath;
  String? newPath;
  bool removed = false;
  PhotoSlot([this.savedPath]);

  /// Is waqt dikhane wali tasveer.
  String? get shown => newPath ?? (removed ? null : savedPath);
  bool get changed => newPath != null || removed;
  bool get hasPhoto => shown != null;
}

/// Bara (chehre ke liye gol) ya chhota (CNIC ke liye) box. Tap: camera / gallery / dekhein / hatayein.
class PhotoSlotBox extends StatefulWidget {
  final PhotoSlot slot;
  final String label;
  final bool round;
  final double size;
  final VoidCallback? onChanged;
  const PhotoSlotBox({super.key, required this.slot, required this.label, this.round = false, this.size = 100, this.onChanged});

  @override
  State<PhotoSlotBox> createState() => _PhotoSlotBoxState();
}

class _PhotoSlotBoxState extends State<PhotoSlotBox> {
  Future<void> _tap() async {
    final s = widget.slot;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (s.hasPhoto)
            ListTile(leading: const Icon(Icons.zoom_in), title: Text(Loc.t('View', 'دیکھیں')), onTap: () => Navigator.pop(ctx, 'view')),
          if (KycPhotoStore.cameraAvailable)
            ListTile(
                leading: const Icon(Icons.photo_camera),
                title: Text(Loc.t('Take photo', 'کیمرے سے تصویر')),
                onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(KycPhotoStore.cameraAvailable ? Loc.t('Choose from gallery', 'گیلری سے چنیں') : Loc.t('Choose file', 'فائل چنیں')),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (s.hasPhoto)
            ListTile(leading: const Icon(Icons.delete_outline), title: Text(Loc.t('Remove', 'ہٹائیں')), onTap: () => Navigator.pop(ctx, 'remove')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'view') {
      final path = s.shown;
      if (path == null) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(child: Image.file(File(path), fit: BoxFit.contain)),
        ),
      );
      return;
    }
    if (choice == 'remove') {
      setState(() {
        s.newPath = null;
        s.removed = true;
      });
      widget.onChanged?.call();
      return;
    }
    try {
      final path = await KycPhotoStore.pickTemp(
          choice == 'camera' ? ImageSource.camera : ImageSource.gallery, maxSide: widget.round ? 900 : 1400);
      if (path == null || !mounted) return;
      setState(() {
        s.newPath = path;
        s.removed = false;
      });
      widget.onChanged?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Loc.t('Photo could not be taken (check camera/photos permission)', 'تصویر نہ لی جا سکی (کیمرہ/فوٹو اجازت دیکھیں)'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final path = widget.slot.shown;
    final w = widget.size;
    final h = widget.round ? widget.size : widget.size * 0.72;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      InkWell(
        customBorder: widget.round ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: _tap,
        child: Container(
          width: w,
          height: h,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.fieldFill,
            shape: widget.round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.round ? null : BorderRadius.circular(12),
            border: Border.all(color: path == null ? p.teal.withOpacity(0.6) : p.border, width: path == null ? 1.6 : 1),
          ),
          child: path == null
              ? Icon(widget.round ? Icons.add_a_photo : Icons.add_photo_alternate_outlined, color: p.teal, size: widget.round ? 34 : 26)
              : Image.file(File(path), fit: BoxFit.cover),
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        width: w + 10,
        child: Text(widget.label,
            textAlign: TextAlign.center, maxLines: 2, style: TextStyle(color: p.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

/// Guarantor (ya koi bhi KYC owner) ki gol tasveer; na ho to naam ka pehla harf.
class KycAvatar extends StatelessWidget {
  final String owner;
  final int id;
  final String name;
  final double radius;
  const KycAvatar({super.key, required this.owner, required this.id, required this.name, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final store = KycPhotoStore.instance;
    return FutureBuilder<void>(
      future: store.ensureLoaded(),
      builder: (context, _) => ValueListenableBuilder<int>(
        valueListenable: store.changes,
        builder: (context, _, __) {
          final path = store.pathFor(owner, id, KycPhotoStore.photo);
          return CircleAvatar(
            radius: radius,
            backgroundColor: p.amber.withOpacity(0.15),
            backgroundImage: path == null ? null : FileImage(File(path)),
            child: path != null
                ? null
                : Text(name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase(),
                    style: TextStyle(color: p.amber, fontWeight: FontWeight.bold, fontSize: radius * 0.8)),
          );
        },
      ),
    );
  }
}
