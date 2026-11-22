import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../db/rx_repository.dart';
import '../theme/theme_manager.dart';

/// Hanna Pharmacy POS: Controlled drugs (℞) register — kis patient ko, kis doctor ki parchi par, kaunsi
/// controlled dawai, kab di. Drug inspector ko dikhane / share karne ke liye.
class RxRegisterScreen extends StatefulWidget {
  const RxRegisterScreen({super.key});

  @override
  State<RxRegisterScreen> createState() => _RxRegisterScreenState();
}

class _RxRegisterScreenState extends State<RxRegisterScreen> {
  int _range = 30; // din; 0 = aaj, -1 = sab
  final _queryCtrl = TextEditingController();
  List<RxRegisterRow>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int? from;
    if (_range == 0) from = today.millisecondsSinceEpoch;
    if (_range > 0) from = today.subtract(Duration(days: _range)).millisecondsSinceEpoch;
    try {
      final rows = await RxRepository.instance.register(fromMillis: from, query: _queryCtrl.text);
      if (mounted) setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _date(int ms) => DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));

  Future<void> _share() async {
    final rows = _rows ?? const [];
    if (rows.isEmpty) return;
    final b = StringBuffer('℞ Controlled Drugs Register\n\n');
    for (final r in rows) {
      b.writeln(_date(r.saleDate));
      b.writeln('Patient: ${r.rx.patientName}${r.rx.patientPhone.isEmpty ? '' : ' (${r.rx.patientPhone})'}');
      b.writeln('Doctor: ${r.rx.doctorName}${r.rx.prescriptionNo.isEmpty ? '' : ' • Parchi ${r.rx.prescriptionNo}'}');
      b.writeln('Bill: ${r.rx.invoice}${r.status == 'active' ? '' : ' (${r.status})'}');
      for (final i in r.items) {
        b.writeln('  - $i');
      }
      b.writeln();
    }
    await Share.share(b.toString(), subject: 'Controlled Drugs Register');
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final rows = _rows;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.navy,
        foregroundColor: Colors.white,
        title: const Text('℞ Controlled Register'),
        actions: [IconButton(icon: const Icon(Icons.share), tooltip: 'Share', onPressed: _share)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in const [(0, 'Aaj'), (7, '7 din'), (30, '30 din'), (-1, 'Sab')])
              ChoiceChip(
                label: Text(f.$2),
                selected: _range == f.$1,
                onSelected: (_) {
                  setState(() => _range = f.$1);
                  _load();
                },
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _queryCtrl,
            onChanged: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Patient, doctor, parchi no. ya dawai…',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: p.fieldFill,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: TextStyle(color: p.red))
          else if (rows == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Koi record nahi.\nProduct mein "℞ Controlled" on karein — phir us dawai ki sale par parchi likhi jayegi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textMuted),
                ),
              ),
            )
          else ...[
            Text('${rows.length} records', style: TextStyle(fontSize: 12, color: p.textMuted)),
            const SizedBox(height: 8),
            for (final r in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: p.cardWhite, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(r.rx.patientName,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.textDark)),
                    ),
                    if (r.status != 'active')
                      Text(r.status, style: TextStyle(fontSize: 11.5, color: p.red, fontWeight: FontWeight.bold)),
                  ]),
                  if (r.rx.patientPhone.isNotEmpty) Text(r.rx.patientPhone, style: TextStyle(fontSize: 12, color: p.textMuted)),
                  const SizedBox(height: 4),
                  Text('Dr. ${r.rx.doctorName}${r.rx.prescriptionNo.isEmpty ? '' : '  •  Parchi ${r.rx.prescriptionNo}'}',
                      style: TextStyle(fontSize: 13, color: p.navy)),
                  const SizedBox(height: 4),
                  for (final i in r.items) Text('℞ $i', style: TextStyle(fontSize: 13, color: p.red)),
                  const SizedBox(height: 4),
                  Text('${_date(r.saleDate)}  •  Bill ${r.rx.invoice}', style: TextStyle(fontSize: 11.5, color: p.textMuted)),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}
