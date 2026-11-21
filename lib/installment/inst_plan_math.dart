import 'dart:convert';
import 'dart:math' as math;

/// Hanna Installment Step 3 — qist plan ka hisaab. Sab PURE (test/installment_plan_test.dart).
///
/// Formula (dukaan par jaise bataya jata hai):
///   baqi (financed) = cash price − advance
///   munafa          = baqi × % (ya fixed raqam)
///   qist ki kul     = baqi + munafa
///   har qist        = kul / mahine, [roundTo] (10 / 50 / 100) tak upar; farq aakhri qist mein
/// Advance alag payment hai (kind = advance), schedule mein nahi.

const freqMonthly = 'monthly';
const freqFortnightly = 'fortnightly';
const freqWeekly = 'weekly';
const freqDaily = 'daily'; // Step 30: rozana qist (rehri / chhota karobar)
const planFrequencies = <String>[freqMonthly, freqFortnightly, freqWeekly, freqDaily];

/// Qiston ki zyada se zyada ginti: rozana 400 tak (takreeban 13 mahine), baqi 60.
int maxInstallments(String frequency) => frequency == freqDaily ? 400 : 60;

const profitPercent = 'percent';
const profitFixed = 'fixed';

const planActive = 'active';
const planCompleted = 'completed';
const planRepossessed = 'repossessed';
const planCancelled = 'cancelled';

const payAdvance = 'advance';
const payInstallment = 'installment';

/// Poori adaigi par chhoot (Step 16): qist mein ginti hoti hai (baqi kam), magar paisa nahi aata (cash row nahi).
const payDiscount = 'discount';

double _r2(double v) => (v * 100).roundToDouble() / 100;

int dayStart(DateTime d) => DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;

/// [from] se [months] mahine aage, wahi tareekh; chhote mahine mein aakhri din (31 Jan + 1 = 28/29 Feb).
DateTime addMonthsClamped(DateTime from, int months) {
  final y = from.year + ((from.month - 1 + months) ~/ 12);
  final m = (from.month - 1 + months) % 12 + 1;
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, math.min(from.day, last));
}

/// Qist number [i] (0 se) ki tareekh (din ki shuruaat, millis).
int dueDateOf(int firstDue, String frequency, int i) {
  final f = DateTime.fromMillisecondsSinceEpoch(firstDue);
  final d = switch (frequency) {
    freqDaily => DateTime(f.year, f.month, f.day + i),
    freqWeekly => DateTime(f.year, f.month, f.day + 7 * i),
    freqFortnightly => DateTime(f.year, f.month, f.day + 15 * i),
    _ => addMonthsClamped(DateTime(f.year, f.month, f.day), i),
  };
  return dayStart(d);
}

class PlanQuote {
  final double cashPrice;
  final double advance;
  final double financed;
  final double profit;

  /// cash price + munafa (customer kul kitna dega, advance samet).
  final double totalPrice;

  /// Advance ke baad qiston mein kitna.
  final double installmentTotal;
  final int count;

  /// Pehli (count − 1) qisten.
  final double each;

  /// Aakhri qist (rounding ka farq).
  final double last;

  const PlanQuote({
    required this.cashPrice,
    required this.advance,
    required this.financed,
    required this.profit,
    required this.totalPrice,
    required this.installmentTotal,
    required this.count,
    required this.each,
    required this.last,
  });

  List<double> get amounts => [for (var i = 0; i < count; i++) i == count - 1 ? last : each];
}

/// Plan ki qisten dobara banana (Step 17, PURE — test/installment_plan_test.dart).
/// [schedule] = purani (tareekh, raqam), [paid] = ab tak ada qist (discount samet, advance nahi). [extra] minus bhi ho sakta
/// hai (exchange mein sasta piece) magar baqi 0 se zyada rehna chahiye.
/// Ada hissa wahi rehta hai (aadhi ada qist tootti hai: ada hissa purani tareekh par), baqi + [extra] (izafi charge)
/// [count] nayi qiston mein [firstDue] se [frequency] par, [roundTo] tak upar gol, farq aakhri qist mein.
List<(int, double)> rescheduleLines({
  required List<(int, double)> schedule,
  required double paid,
  required int count,
  required int firstDue,
  required String frequency,
  double extra = 0,
  int roundTo = 1,
}) {
  if (!planFrequencies.contains(frequency)) throw ArgumentError('Qist ka waqfa chunein.');
  if (count < 1 || count > maxInstallments(frequency)) throw ArgumentError('Qisten 1 se ${maxInstallments(frequency)} tak.');
  if (!extra.isFinite) throw ArgumentError('Izafi raqam theek nahi.'); // minus = kam (saman badalne par sasta piece)
  if (firstDue <= 0) throw ArgumentError('Pehli qist ki tareekh chunein.');
  if (!planFrequencies.contains(frequency)) throw ArgumentError('Qist ka waqfa chunein.');
  final kept = <(int, double)>[];
  var left = paid < 0 ? 0.0 : paid;
  var total = 0.0;
  for (final (due, amt) in schedule) {
    total += amt;
    if (left <= 0.005) continue;
    final take = math.min(left, amt);
    kept.add((due, _r2(take)));
    left = _r2(left - take);
  }
  final remaining = _r2(total - (paid < 0 ? 0 : math.min(paid, total)) + extra);
  if (remaining <= 0.5) throw ArgumentError('Is plan ka koi baqi nahi — qisten badalne ki zaroorat nahi.');
  final step = roundTo < 1 ? 1 : roundTo;
  var each = ((remaining / count) / step).ceil() * step.toDouble();
  var last = _r2(remaining - each * (count - 1));
  if (count > 1 && last <= 0) {
    each = ((remaining / count) / step).floor() * step.toDouble();
    if (each <= 0) each = (remaining / count).floorToDouble();
    last = _r2(remaining - each * (count - 1));
  }
  if (count == 1) {
    each = remaining;
    last = remaining;
  }
  return [
    ...kept,
    for (var i = 0; i < count; i++) (dueDateOf(firstDue, frequency, i), i == count - 1 ? last : _r2(each)),
  ];
}

/// Qist ki raqam. Galat input => [ArgumentError] (message screen par dikhta hai).
PlanQuote quotePlan({
  required double cashPrice,
  required double advance,
  required String profitMode,
  required double profitValue,
  required int count,
  int roundTo = 1,
  String frequency = freqMonthly, // sirf ginti ki hadd ke liye (rozana 400 tak)
}) {
  if (!cashPrice.isFinite || cashPrice <= 0) throw ArgumentError('Sale price likhein.');
  if (!advance.isFinite || advance < 0) throw ArgumentError('Advance minus nahi ho sakta.');
  if (advance >= cashPrice) throw ArgumentError('Advance poori qeemat ke barabar ya zyada hai — ye cash sale hai, qist nahi.');
  if (count < 1 || count > maxInstallments(frequency)) throw ArgumentError('Qisten 1 se ${maxInstallments(frequency)} tak.');
  if (!profitValue.isFinite || profitValue < 0) throw ArgumentError('Munafa minus nahi ho sakta.');
  if (profitMode == profitPercent && profitValue > 300) throw ArgumentError('Munafa % bohat zyada hai.');
  final financed = _r2(cashPrice - advance);
  final profit = _r2(profitMode == profitFixed ? profitValue : financed * profitValue / 100);
  final instTotal = _r2(financed + profit);
  final step = roundTo < 1 ? 1 : roundTo;
  var each = ((instTotal / count) / step).ceil() * step.toDouble();
  var last = _r2(instTotal - each * (count - 1));
  if (count > 1 && last <= 0) {
    // Upar round karne se aakhri qist khatam ho gayi (chhoti raqam, bari rounding) — neeche round karo.
    each = ((instTotal / count) / step).floor() * step.toDouble();
    // Rounding itni bari ke qist 0 ban jaye: rounding chhor do (poore rupay).
    if (each <= 0) each = (instTotal / count).floorToDouble();
    last = _r2(instTotal - each * (count - 1));
  }
  if (count == 1) {
    each = instTotal;
    last = instTotal;
  }
  return PlanQuote(
    cashPrice: _r2(cashPrice),
    advance: _r2(advance),
    financed: financed,
    profit: profit,
    totalPrice: _r2(cashPrice + profit),
    installmentTotal: instTotal,
    count: count,
    each: _r2(each),
    last: last,
  );
}

// ------------------------------------------------------------------ status

enum InstallmentState { paid, partial, dueToday, overdue, upcoming }

class ScheduleLine {
  final int seq;
  final int dueDate;
  final double amount;
  final double paid;
  final InstallmentState state;
  const ScheduleLine({required this.seq, required this.dueDate, required this.amount, required this.paid, required this.state});

  double get remaining => _r2(math.max(0, amount - paid));
}

class PlanStatus {
  final List<ScheduleLine> lines;

  /// Qiston mein ab tak (advance aur fine ke baghair).
  final double paid;
  final double installmentTotal;
  final double remaining;

  /// Aaj se pehle wali (aur aaj ki) qiston ka baqi.
  final double dueNow;

  /// Sirf aaj se pehle wali (late) qiston ka baqi.
  final double overdue;
  final int overdueCount;

  /// Sab se purani late qist kitne din se late (0 = koi nahi).
  final int daysLate;

  /// Agli na-adaa qist (null = sab adaa).
  final ScheduleLine? next;

  const PlanStatus({
    required this.lines,
    required this.paid,
    required this.installmentTotal,
    required this.remaining,
    required this.dueNow,
    required this.overdue,
    required this.overdueCount,
    required this.daysLate,
    required this.next,
  });

  bool get fullyPaid => remaining <= 0.5;
}

/// Payments ko tarteeb se qiston par lagata hai (pehli qist pehle). [today] = din ki shuruaat.
PlanStatus planStatus({
  required List<(int, double)> schedule, // (dueDate, amount), seq ke hisaab se
  required double paidInstallments,
  required int today,
}) {
  var left = paidInstallments;
  final lines = <ScheduleLine>[];
  double dueNow = 0, overdue = 0, total = 0;
  var overdueCount = 0;
  var oldestLate = 0;
  ScheduleLine? next;
  for (var i = 0; i < schedule.length; i++) {
    final (due, amt) = schedule[i];
    total += amt;
    final pay = math.min(math.max(left, 0.0), amt);
    left -= pay;
    final rem = amt - pay;
    final InstallmentState st;
    if (rem <= 0.5) {
      st = InstallmentState.paid;
    } else if (due < today) {
      st = InstallmentState.overdue;
    } else if (due == today) {
      st = InstallmentState.dueToday;
    } else {
      st = pay > 0.5 ? InstallmentState.partial : InstallmentState.upcoming;
    }
    final line = ScheduleLine(seq: i + 1, dueDate: due, amount: _r2(amt), paid: _r2(pay), state: st);
    lines.add(line);
    if (st != InstallmentState.paid) {
      next ??= line;
      if (due <= today) dueNow += rem;
      if (due < today) {
        overdue += rem;
        overdueCount++;
        if (oldestLate == 0) oldestLate = due;
      }
    }
  }
  final daysLate = oldestLate == 0
      ? 0
      : DateTime.fromMillisecondsSinceEpoch(today).difference(DateTime.fromMillisecondsSinceEpoch(oldestLate)).inHours ~/ 24;
  final paid = _r2(math.min(paidInstallments, total));
  return PlanStatus(
    lines: lines,
    paid: paid,
    installmentTotal: _r2(total),
    remaining: _r2(math.max(0, total - paidInstallments)),
    dueNow: _r2(dueNow),
    overdue: _r2(overdue),
    overdueCount: overdueCount,
    daysLate: daysLate,
    next: next,
  );
}

/// Late fine ka mashwara: har woh qist jo [graceDays] se zyada late hai × [lateFee] − jo fine pehle le chuke.
/// Sirf mashwara — wasooli par dukaandar kam / zyada / 0 kar sakta hai.
double suggestedFine({
  required PlanStatus status,
  required double lateFee,
  required int graceDays,
  required int today,
  double finesAlreadyTaken = 0,
}) {
  if (lateFee <= 0) return 0;
  final cutoff = DateTime.fromMillisecondsSinceEpoch(today).subtract(Duration(days: graceDays < 0 ? 0 : graceDays));
  final cutoffMs = dayStart(cutoff);
  var n = 0;
  for (final l in status.lines) {
    if (l.state == InstallmentState.overdue && l.dueDate < cutoffMs) n++;
  }
  return _r2(math.max(0, n * lateFee - finesAlreadyTaken));
}

List<int> parseIdList(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    final v = jsonDecode(raw);
    if (v is! List) return const [];
    return [for (final e in v) if (e is num) e.toInt()];
  } catch (_) {
    return const [];
  }
}

/// Customer ko bhejne wali receipt (WhatsApp / share). Sada text, Urdu + English.
String receiptText({
  required String shopName,
  required String planNo,
  required String customerName,
  required String itemTitle,
  required double amount,
  required double fine,
  required String method,
  required int paidAt,
  required double remaining,
  required int? nextDue,
  required double nextAmount,
  String kind = payInstallment,
}) {
  String d(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.day.toString().padLeft(2, '0')}-${t.month.toString().padLeft(2, '0')}-${t.year}';
  }

  String rs(double v) => 'Rs ${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(2)}';
  final b = StringBuffer()
    ..writeln(shopName.trim().isEmpty ? 'Installment Receipt' : shopName.trim())
    ..writeln('------------------------')
    ..writeln('Plan: $planNo')
    ..writeln('Customer: $customerName')
    ..writeln('Item: $itemTitle')
    ..writeln('Date: ${d(paidAt)}')
    ..writeln(kind == payDiscount
        ? 'Discount: ${rs(amount)}'
        : '${kind == payAdvance ? 'Advance' : 'Installment'} received: ${rs(amount)} (${method == 'bank' ? 'Bank' : 'Cash'})');
  if (fine > 0) b.writeln('Late fine: ${rs(fine)}');
  b.writeln('Remaining: ${rs(remaining)}');
  if (nextDue != null && remaining > 0.5) b.writeln('Next installment: ${rs(nextAmount)} on ${d(nextDue)}');
  if (remaining <= 0.5) b.writeln('Plan complete. Thank you!');
  b
    ..writeln('------------------------')
    ..write(shopName.trim().isEmpty ? 'Thank you!' : 'Thank you — ${shopName.trim()}');
  return b.toString();
}
