import 'package:flutter/material.dart';

import '../db/rx_repository.dart';
import '../theme/theme_manager.dart';

/// Hanna Pharmacy POS: Controlled (℞) dawai bechne se pehle patient / doctor / parchi number.
/// Patient aur Doctor ka naam zaroori. null = cashier ne Cancel kiya (bill save nahi hona chahiye).
/// Lautaya hua record ka `invoice` khali hota hai — caller save ke baad lagata hai.
Future<RxRecord?> askRxDetails(BuildContext context, {required List<String> medicines, RxRecord? initial}) {
  return showDialog<RxRecord>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RxDialog(medicines: medicines, initial: initial),
  );
}

class _RxDialog extends StatefulWidget {
  const _RxDialog({required this.medicines, this.initial});
  final List<String> medicines;
  final RxRecord? initial;

  @override
  State<_RxDialog> createState() => _RxDialogState();
}

class _RxDialogState extends State<_RxDialog> {
  late final _patient = TextEditingController(text: widget.initial?.patientName ?? '');
  late final _phone = TextEditingController(text: widget.initial?.patientPhone ?? '');
  late final _doctor = TextEditingController(text: widget.initial?.doctorName ?? '');
  late final _rxNo = TextEditingController(text: widget.initial?.prescriptionNo ?? '');
  String? _error;

  @override
  void dispose() {
    _patient.dispose();
    _phone.dispose();
    _doctor.dispose();
    _rxNo.dispose();
    super.dispose();
  }

  void _ok() {
    final patient = _patient.text.trim();
    final doctor = _doctor.text.trim();
    if (patient.isEmpty || doctor.isEmpty) {
      setState(() => _error = 'Patient aur Doctor ka naam zaroori hai');
      return;
    }
    Navigator.of(context).pop(RxRecord(
      invoice: '',
      patientName: patient,
      patientPhone: _phone.text.trim(),
      doctorName: doctor,
      prescriptionNo: _rxNo.text.trim(),
      createdAt: widget.initial?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Widget _field(TextEditingController c, String label, {TextInputType? type, bool last = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: type,
          textCapitalization: TextCapitalization.words,
          textInputAction: last ? TextInputAction.done : TextInputAction.next,
          onSubmitted: last ? (_) => _ok() : null,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    return AlertDialog(
      title: const Text('℞ Parchi ki tafseel'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Controlled dawai: ${widget.medicines.join(', ')}', style: TextStyle(fontSize: 12.5, color: p.red)),
          const SizedBox(height: 12),
          _field(_patient, 'Patient ka naam *'),
          _field(_phone, 'Patient ka phone (optional)', type: TextInputType.phone),
          _field(_doctor, 'Doctor ka naam *'),
          _field(_rxNo, 'Parchi / Prescription No. (optional)', last: true),
          if (_error != null) Text(_error!, style: TextStyle(color: p.red, fontSize: 12.5)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _ok, child: const Text('Save')),
      ],
    );
  }
}
