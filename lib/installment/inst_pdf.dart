import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart'
    show BuildContext, Column, Icon, Icons, ListTile, MainAxisSize, Navigator, SafeArea, ScaffoldMessenger, SnackBar, Text, showModalBottomSheet;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/due_reminders_repository.dart' show whatsAppDigits;
import '../services/party_photo_store.dart';
import '../services/slip_pdf_service.dart';
import '../services/whatsapp_pdf.dart';
import '../services/whatsapp_sender.dart';
import '../utils/loc.dart';
import '../utils/pdf_urdu.dart';
import '../utils/slip_pdf_data.dart' show slipFileName;
import 'inst_csv.dart';
import 'inst_plan_math.dart';
import 'inst_plan_repository.dart';
import 'inst_repository.dart';
import 'inst_signature.dart' show planSignCustomer, planSignGuarantor;
import 'inst_terms.dart';
import 'shop_logo.dart';
import 'kyc_photo_store.dart';

/// Qist ke PDF: (1) plan statement / agreement — customer + zamin ki tasveerein, CNIC, saman, schedule,
/// wasooli, dastakhat; (2) ek wasooli ki receipt. Urdu text [UrduPdf] se (Noto Nastaliq tasveer), POS slips jaisa.
class InstPdf {
  InstPdf._();

  static const _teal = PdfColor.fromInt(0xFF0F9B8E);
  static const _navy = PdfColor.fromInt(0xFF2E3242);
  static const _gray = PdfColor.fromInt(0xFF8A90A6);
  static const _line = PdfColor.fromInt(0xFFE3E6EF);
  static const _red = PdfColor.fromInt(0xFFD64545);

  static pw.Font? _urduFont;
  static pw.MemoryImage? _logo;
  static pw.MemoryImage? _appLogo;
  static bool _logoTried = false;

  static String _rs(double v) {
    final f = NumberFormat('#,##0.##');
    return 'Rs ${f.format(v)}';
  }

  static String _d(int ms) => DateFormat('dd-MM-yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));

  static Future<void> _assets() async {
    if (_urduFont == null) {
      for (final path in const ['assets/fonts/NotoNaskhArabic-Regular.ttf', 'assets/fonts/UrduFallback.ttf']) {
        try {
          _urduFont = pw.Font.ttf(await rootBundle.load(path));
          break;
        } catch (_) {}
      }
    }
    if (!_logoTried) {
      _logoTried = true;
      try {
        _appLogo = pw.MemoryImage((await rootBundle.load('assets/images/logo.png')).buffer.asUint8List());
      } catch (_) {}
    }
    // Step 31: dukaan ka apna logo (Settings > Shop Information) — warna dukaan ka naam ho to koi logo nahi
    // (app ka naam / logo customer ke kaghaz par nahi), naam bhi na ho to app ka logo.
    final shopLogo = await _img(await ShopLogo.path());
    if (shopLogo != null) {
      _logo = shopLogo;
    } else {
      final name = (await loadShopHeader()).name;
      _logo = name.isEmpty ? _appLogo : null;
    }
  }

  static Future<pw.MemoryImage?> _img(String? path) async {
    if (path == null) return null;
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return pw.MemoryImage(await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static pw.Widget _t(String t, {double size = 10, bool bold = false, int argb = 0xFF2E3242, pw.TextAlign? align}) {
    final img = UrduPdf.widget(t, fontSize: size, argb: argb, bold: bold);
    if (img != null) return img;
    return pw.Text(t,
        textAlign: align,
        style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: PdfColor.fromInt(argb)));
  }

  static pw.Widget _kv(String k, String v, {bool bold = false, int argb = 0xFF2E3242}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 95, child: _t(k, size: 9.5, argb: 0xFF8A90A6)),
          pw.Expanded(child: _t(v.isEmpty ? '-' : v, size: 10, bold: bold, argb: argb)),
        ]),
      );

  static pw.Widget _photo(pw.MemoryImage? img, double w, double h, String caption) => pw.Column(children: [
        pw.Container(
          width: w,
          height: h,
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(4)),
          child: img == null ? pw.Center(child: _t(Loc.t('No photo', 'تصویر نہیں'), size: 8, argb: 0xFF8A90A6)) : pw.Image(img, fit: pw.BoxFit.cover),
        ),
        pw.SizedBox(height: 2),
        _t(caption, size: 8, argb: 0xFF8A90A6),
      ]);

  static pw.Widget _section(String title) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
        padding: const pw.EdgeInsets.only(bottom: 2),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _teal, width: 0.8))),
        child: _t(title, size: 11, bold: true, argb: 0xFF0F9B8E),
      );

  static pw.Widget _header(ShopHeader shop, String title, String sub) => pw.Row(children: [
        if (_logo != null) pw.Container(width: 38, height: 38, margin: const pw.EdgeInsets.only(right: 10), child: pw.Image(_logo!)),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _t(shop.name.isEmpty ? 'Hanna Installment' : shop.name, size: 15, bold: true),
            if (shop.phone.isNotEmpty) _t(shop.phone, size: 9, argb: 0xFF8A90A6),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _t(title, size: 13, bold: true, argb: 0xFF0F9B8E),
          _t(sub, size: 9, argb: 0xFF8A90A6),
        ]),
      ]);

  /// RAM kam ho to ek baar chhoti Urdu tasveeron ke saath dobara.
  static Future<Uint8List> _safe(Future<Uint8List> Function() make) async {
    try {
      return await make();
    } catch (_) {
      UrduPdf.setLean(true);
      try {
        return await make();
      } finally {
        UrduPdf.setLean(false);
        UrduPdf.clearCache();
      }
    }
  }

  static pw.Document _doc() => pw.Document(
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          fontFallback: _urduFont == null ? const [] : [_urduFont!],
        ),
      );

  // ================================================================ statement

  static Future<Uint8List> statementBytes(PlanView v) => _safe(() => _statement(v));

  static Future<Uint8List> _statement(PlanView v) async {
    await _assets();
    final shop = await loadShopHeader();
    final terms = InstTerms.lines(await InstTerms.load());
    final secs = await InstPlanRepository.instance.securities(v.plan.id);
    final repo = InstRepository.instance;
    final prof = await repo.profile(v.plan.customerId);
    final allG = await repo.guarantors(v.plan.customerId);
    final gs = allG.where((g) => v.plan.guarantorIds.contains(g.id)).toList();
    await PartyPhotoStore.instance.ensureLoaded();
    await KycPhotoStore.instance.ensureLoaded();
    final kyc = KycPhotoStore.instance;
    final face = await _img(PartyPhotoStore.instance.pathFor(true, v.plan.customerId));
    final cF = await _img(kyc.pathFor('c', v.plan.customerId, KycPhotoStore.cnicFront));
    // Step 32: plan banate waqt liye gaye dastakhat.
    final sigC = await _img(kyc.pathFor('p', v.plan.id, planSignCustomer));
    final sigG = await _img(kyc.pathFor('p', v.plan.id, planSignGuarantor));
    final cB = await _img(kyc.pathFor('c', v.plan.customerId, KycPhotoStore.cnicBack));
    final gPhotos = <int, (pw.MemoryImage?, pw.MemoryImage?)>{};
    for (final g in gs) {
      gPhotos[g.id!] = (await _img(kyc.pathFor('g', g.id!, KycPhotoStore.photo)), await _img(kyc.pathFor('g', g.id!, KycPhotoStore.cnicFront)));
    }

    List<pw.Widget> build() {
      final st = v.status;
      final it = v.item;
      return [
        _header(shop, Loc.t('Installment Statement', 'قسط اسٹیٹمنٹ'), '${v.plan.planNo}  •  ${_d(DateTime.now().millisecondsSinceEpoch)}'),
        pw.SizedBox(height: 6),
        _section(Loc.t('Customer', 'خریدار')),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(children: [
              _kv(Loc.t('Name', 'نام'), v.customerName, bold: true),
              _kv(Loc.t('Father / husband', 'والد / شوہر'), prof?.fatherName ?? ''),
              _kv(Loc.t('CNIC', 'شناختی کارڈ'), prof?.cnic ?? ''),
              _kv(Loc.t('Phone', 'فون'), [v.customerPhone, prof?.phone2 ?? ''].where((s) => s.isNotEmpty).join(' / ')),
              _kv(Loc.t('Address', 'پتہ'), prof?.address ?? ''),
              _kv(Loc.t('Job / business', 'روزگار'), prof?.occupation ?? ''),
            ]),
          ),
          pw.SizedBox(width: 8),
          _photo(face, 62, 74, Loc.t('Photo', 'تصویر')),
          pw.SizedBox(width: 6),
          _photo(cF, 92, 60, Loc.t('CNIC front', 'کارڈ سامنے')),
          pw.SizedBox(width: 6),
          _photo(cB, 92, 60, Loc.t('CNIC back', 'کارڈ پیچھے')),
        ]),
        _section(Loc.t('Guarantors', 'ضامن')),
        if (gs.isEmpty) _t(Loc.t('None', 'کوئی نہیں'), size: 9.5, argb: 0xFF8A90A6),
        for (final g in gs)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(
                child: pw.Column(children: [
                  _kv(Loc.t('Name', 'نام'), [g.name, if (g.relation.isNotEmpty) '(${g.relation})'].join(' '), bold: true),
                  _kv(Loc.t('Father', 'والد'), g.fatherName),
                  _kv(Loc.t('CNIC', 'شناختی کارڈ'), g.cnic),
                  _kv(Loc.t('Phone', 'فون'), g.phone),
                  _kv(Loc.t('Address', 'پتہ'), g.address),
                ]),
              ),
              pw.SizedBox(width: 8),
              _photo(gPhotos[g.id]?.$1, 52, 62, Loc.t('Photo', 'تصویر')),
              pw.SizedBox(width: 6),
              _photo(gPhotos[g.id]?.$2, 86, 56, Loc.t('CNIC', 'کارڈ')),
            ]),
          ),
        _section(Loc.t('Item', 'سامان')),
        _kv(Loc.t('Item', 'سامان'), v.itemTitle, bold: true),
        if (it != null && it.color.isNotEmpty) _kv(Loc.t('Color', 'رنگ'), it.color),
        if (it != null) for (final e in it.idValues.entries) _kv(e.key, e.value),
        if (it != null && it.warrantyMonths > 0) _kv(Loc.t('Warranty', 'وارنٹی'), '${it.warrantyMonths} ${Loc.t('months', 'مہینے')}'),
        _section(Loc.t('Plan', 'پلان')),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(children: [
              _kv(Loc.t('Cash price', 'نقد قیمت'), _rs(v.plan.cashPrice)),
              _kv(Loc.t('Total price', 'کل قیمت'), _rs(v.plan.totalPrice), bold: true),
              _kv(Loc.t('Advance', 'ایڈوانس'), _rs(v.plan.advance)),
              _kv(Loc.t('Installments', 'قسطیں'), '${v.plan.count}  (${v.plan.frequency})'),
            ]),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(children: [
              _kv(Loc.t('Received', 'وصول'), _rs(st.paid + v.advancePaid), argb: 0xFF0F9B8E, bold: true),
              _kv(Loc.t('Remaining', 'باقی'), _rs(st.remaining), bold: true),
              _kv(Loc.t('Late', 'لیٹ'), st.overdue > 0.5 ? '${_rs(st.overdue)}  (${st.daysLate} ${Loc.t('days', 'دن')})' : '-',
                  argb: st.overdue > 0.5 ? 0xFFD64545 : 0xFF2E3242),
              if (v.plan.lateFee > 0)
                _kv(Loc.t('Late fine', 'لیٹ جرمانہ'), '${_rs(v.plan.lateFee)} / ${Loc.t('qist', 'قسط')} (${v.plan.graceDays} ${Loc.t('days grace', 'دن رعایت')})'),
            ]),
          ),
        ]),
        _section(Loc.t('Schedule', 'قسطوں کا شیڈول')),
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
          columnWidths: {
            0: pw.FixedColumnWidth(24),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2),
            4: pw.FlexColumnWidth(1.6),
          },
          children: [
            pw.TableRow(children: [
              for (final h in ['#', Loc.t('Due date', 'تاریخ'), Loc.t('Amount', 'رقم'), Loc.t('Paid', 'ادا'), Loc.t('Status', 'حالت')])
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: _t(h, size: 9, bold: true, argb: 0xFF8A90A6)),
            ]),
            for (final l in st.lines)
              pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.5), child: _t('${l.seq}', size: 9)),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.5), child: _t(_d(l.dueDate), size: 9)),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.5), child: _t(_rs(l.amount), size: 9)),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.5), child: _t(l.paid > 0 ? _rs(l.paid) : '-', size: 9)),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                  child: _t(_state(l.state),
                      size: 9,
                      bold: l.state == InstallmentState.overdue,
                      argb: l.state == InstallmentState.overdue
                          ? 0xFFD64545
                          : (l.state == InstallmentState.paid ? 0xFF0F9B8E : 0xFF2E3242)),
                ),
              ]),
          ],
        ),
        if (v.payments.isNotEmpty) ...[
          _section(Loc.t('Payments received', 'وصولیاں')),
          for (final pay in v.payments.reversed)
            _kv(_d(pay.paidAt),
                '${pay.kind == payAdvance ? Loc.t('Advance', 'ایڈوانس') : (pay.kind == payDiscount ? Loc.t('Discount', 'رعایت') : Loc.t('Qist', 'قسط'))}  ${_rs(pay.amount)}'
                '${pay.fine > 0 ? '  + ${Loc.t('fine', 'جرمانہ')} ${_rs(pay.fine)}' : ''}  (${pay.method})'),
        ],
        if (secs.isNotEmpty) ...[
          _section(Loc.t('Security documents', 'ضمانت کے کاغذات')),
          for (final sc in secs)
            _kv(
                sc.kind == securityCheque
                    ? Loc.t('Cheque', 'چیک')
                    : (sc.kind == securityStamp ? Loc.t('Stamp paper', 'اسٹامپ پیپر') : Loc.t('Document', 'کاغذ')),
                [
                  if (sc.number.isNotEmpty) '#${sc.number}',
                  if (sc.bank.isNotEmpty) sc.bank,
                  if (sc.amount > 0) _rs(sc.amount),
                  if (sc.note.isNotEmpty) sc.note,
                  sc.returned ? '${Loc.t('returned', 'واپس')} ${_d(sc.returnedAt)}' : Loc.t('with shop', 'دکان کے پاس'),
                ].join('  •  ')),
        ],
        if (terms.isNotEmpty) ...[
          _section(Loc.t('Terms / agreement', 'شرائط / اقرار نامہ')),
          for (final line in terms) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: _t(line, size: 9.5)),
          pw.SizedBox(height: 4),
          _t(Loc.t('We have read and accept the above terms.', 'ہم نے اوپر دی گئی شرائط پڑھ کر قبول کیں۔'), size: 9, argb: 0xFF8A90A6),
        ],
        pw.SizedBox(height: sigC != null || sigG != null ? 8 : 26),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          for (final (s, img) in [
            (Loc.t('Customer signature', 'خریدار کے دستخط'), sigC),
            (Loc.t('Guarantor signature', 'ضامن کے دستخط'), sigG),
            (Loc.t('Shop', 'دکان'), null),
          ])
            pw.Expanded(
              child: pw.Column(children: [
                if (img != null) pw.Container(height: 46, child: pw.Image(img, fit: pw.BoxFit.contain)),
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(horizontal: 8),
                  padding: const pw.EdgeInsets.only(top: 3),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _navy, width: 0.6))),
                  child: pw.Center(child: _t(s, size: 8.5, argb: 0xFF8A90A6)),
                ),
              ]),
            ),
        ]),
      ];
    }

    final doc = _doc();
    build(); // pass 1: Urdu text yaad
    await UrduPdf.flush();
    final widgets = build();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
      maxPages: 20,
      build: (_) => widgets,
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${v.plan.planNo}  •  ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _gray)),
      ),
    ));
    final bytes = await doc.save();
    UrduPdf.clearCache();
    return bytes;
  }

  static String _state(InstallmentState s) => switch (s) {
        InstallmentState.paid => Loc.t('Paid', 'ادا'),
        InstallmentState.partial => Loc.t('Part', 'کچھ ادا'),
        InstallmentState.dueToday => Loc.t('Today', 'آج'),
        InstallmentState.overdue => Loc.t('Late', 'لیٹ'),
        InstallmentState.upcoming => Loc.t('Upcoming', 'آنے والی'),
      };

  // ================================================================ receipt

  static Future<Uint8List> receiptBytes(PlanView v, InstPayment pay, {required double remainingAfter}) =>
      _safe(() => _receipt(v, pay, remainingAfter));

  static Future<Uint8List> _receipt(PlanView v, InstPayment pay, double remainingAfter) async {
    await _assets();
    final shop = await loadShopHeader();
    await PartyPhotoStore.instance.ensureLoaded();
    final face = await _img(PartyPhotoStore.instance.pathFor(true, v.plan.customerId));
    final next = v.status.next;
    // Receipt hamesha English mein (Step 30) — customer / doosre log aasani se parh sakein.

    List<pw.Widget> build() => [
          _header(shop, 'Receipt', '${v.plan.planNo}-${pay.id}'),
          pw.SizedBox(height: 8),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(children: [
                _kv('Customer', v.customerName, bold: true),
                _kv('Item', v.itemTitle),
                if (v.item != null && v.item!.primaryId.isNotEmpty) _kv('ID', v.item!.primaryId),
                _kv('Date', DateFormat('dd-MM-yyyy  h:mm a').format(DateTime.fromMillisecondsSinceEpoch(pay.paidAt))),
              ]),
            ),
            if (face != null) _photo(face, 54, 64, ''),
          ]),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 10),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _teal, width: 1), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              _kv(pay.kind == payAdvance ? 'Advance' : (pay.kind == payDiscount ? 'Discount' : 'Installment received'), _rs(pay.amount), bold: true, argb: 0xFF0F9B8E),
              if (pay.fine > 0) _kv('Late fine', _rs(pay.fine)),
              _kv('Total', _rs(pay.amount + pay.fine), bold: true),
              _kv('Method', pay.method == 'bank' ? 'Bank' : 'Cash'),
              if (pay.receivedBy.isNotEmpty) _kv('Received by', pay.receivedBy),
            ]),
          ),
          _kv('Remaining', _rs(remainingAfter), bold: true, argb: remainingAfter > 0.5 ? 0xFF2E3242 : 0xFF0F9B8E),
          if (remainingAfter > 0.5 && next != null)
            _kv('Next installment', '${_rs(next.remaining)}  —  ${_d(next.dueDate)}'),
          if (remainingAfter <= 0.5) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: _t('Plan complete. Thank you!', size: 12, bold: true, argb: 0xFF0F9B8E)),
          if (v.status.overdue > 0.5)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: _t('Late amount: ${_rs(v.status.overdue)}', size: 10, bold: true, argb: 0xFFD64545),
            ),
        ];

    final doc = _doc();
    build();
    await UrduPdf.flush();
    final widgets = build();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.fromLTRB(26, 26, 26, 26),
      maxPages: 3,
      build: (_) => widgets,
    ));
    final bytes = await doc.save();
    UrduPdf.clearCache();
    return bytes;
  }

  // ================================================================ report table (Step 14)

  /// Kisi bhi report ki A4 jadwal PDF: upar dukaan + unwan, phir khulasa (label: value), phir jadwal.
  /// [flex] = har column ki chaurai (na do to barabar); [right] = jo columns daen taraf (raqam).
  static Future<Uint8List> tableBytes({
    required String title,
    required String sub,
    List<(String, String)> summary = const [],
    required List<String> headers,
    required List<List<String>> rows,
    List<int>? flex,
    Set<int> right = const {},
  }) =>
      _safe(() => _table(title, sub, summary, headers, rows, flex, right));

  static Future<Uint8List> _table(String title, String sub, List<(String, String)> summary, List<String> headers,
      List<List<String>> rows, List<int>? flex, Set<int> right) async {
    await _assets();
    final shop = await loadShopHeader();
    final fl = flex != null && flex.length == headers.length ? flex : List<int>.filled(headers.length, 1);
    pw.Widget cell(String t, int i, {bool head = false}) => pw.Expanded(
          flex: fl[i],
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            child: pw.Align(
              alignment: right.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
              child: _t(t, size: 8.5, bold: head, argb: head ? 0xFFFFFFFF : 0xFF2E3242),
            ),
          ),
        );
    List<pw.Widget> build() => [
          _header(shop, title, sub),
          pw.SizedBox(height: 8),
          for (final s in summary) _kv(s.$1, s.$2, bold: true),
          if (summary.isNotEmpty) pw.SizedBox(height: 8),
          pw.Container(
            color: _navy,
            child: pw.Row(children: [for (var i = 0; i < headers.length; i++) cell(headers[i], i, head: true)]),
          ),
          for (var r = 0; r < rows.length; r++)
            pw.Container(
              decoration: pw.BoxDecoration(
                color: r.isOdd ? const PdfColor.fromInt(0xFFF5F6FA) : PdfColors.white,
                border: const pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5)),
              ),
              child: pw.Row(children: [
                for (var i = 0; i < headers.length; i++) cell(i < rows[r].length ? rows[r][i] : '', i),
              ]),
            ),
          if (rows.isEmpty) pw.Padding(padding: const pw.EdgeInsets.all(12), child: _t('—', argb: 0xFF8A90A6)),
        ];
    final doc = _doc();
    build(); // pass 1: Urdu text yaad
    await UrduPdf.flush();
    final widgets = build();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(26, 26, 26, 26),
      maxPages: 60,
      build: (_) => widgets,
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${_d(DateTime.now().millisecondsSinceEpoch)}  •  ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _gray)),
      ),
    ));
    final bytes = await doc.save();
    UrduPdf.clearCache();
    return bytes;
  }

  /// Report PDF bana kar share sheet (WhatsApp / print / save).
  static Future<void> shareTable(
    BuildContext context, {
    required String base,
    required String title,
    required String sub,
    List<(String, String)> summary = const [],
    required List<String> headers,
    required List<List<String>> rows,
    List<int>? flex,
    Set<int> right = const {},
  }) async {
    // Step 25: PDF ya Excel (CSV).
    final fmt = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(Loc.t('PDF (print / WhatsApp)', 'PDF (پرنٹ / واٹس ایپ)')),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(Loc.t('Excel (CSV)', 'ایکسل (CSV)')),
            onTap: () => Navigator.pop(ctx, 'csv'),
          ),
        ]),
      ),
    );
    if (fmt == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (fmt == 'csv') {
      try {
        await InstCsv.share(base: base, text: csvText(title: title, sub: sub, summary: summary, headers: headers, rows: rows));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(Loc.t('File could not be made: $e', 'فائل نہ بن سکی: $e'))));
      }
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(Loc.t('Making PDF...', 'PDF بن رہی ہے...'))));
    final bytes = await tableBytes(title: title, sub: sub, summary: summary, headers: headers, rows: rows, flex: flex, right: right);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    await send(context, bytes: bytes, base: base, phone: '');
  }

  // ================================================================ files / share

  static Future<File> _write(Uint8List bytes, String base) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'slips'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final f = File(p.join(dir.path, slipFileName(base, DateTime.now())));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// PDF bana kar: Android par seedha customer ki WhatsApp chat, warna share sheet.
  static Future<void> send(BuildContext context, {required Uint8List bytes, required String base, required String phone, String text = ''}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final f = await _write(bytes, base);
      final digits = whatsAppDigits(phone);
      if (digits.isNotEmpty && await WhatsAppPdf.send(f, digits, text: text)) return;
      await SlipPdfService.shareFile(f, subject: base);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(Loc.t('PDF could not be made: $e', 'PDF نہ بن سکی: $e'))));
    }
  }

  static Future<void> sendStatement(BuildContext context, PlanView v) async {
    final bytes = await statementBytes(v);
    if (!context.mounted) return;
    await send(context, bytes: bytes, base: '${v.plan.planNo}_${v.customerName}', phone: v.customerPhone);
  }

  static Future<void> sendReceipt(BuildContext context, PlanView v, InstPayment pay, {required double remainingAfter}) async {
    final bytes = await receiptBytes(v, pay, remainingAfter: remainingAfter);
    if (!context.mounted) return;
    await send(context, bytes: bytes, base: 'Receipt_${v.plan.planNo}_${v.customerName}', phone: v.customerPhone);
  }
}
