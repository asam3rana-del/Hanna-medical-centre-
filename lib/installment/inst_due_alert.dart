import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/due_alert_service.dart';
import 'inst_plan_math.dart';
import 'inst_plan_repository.dart';

/// Roz subah ki notification: "Aaj 5 qisten (Rs 21,000) • 3 late (Rs 9,000). Pehle: Ali, Usman...".
/// Tap par Wasooli List khulti hai (payload [payload], DueAlertService._open). Din mein ek baar, [alertHour] ke baad.
/// Foreground (app khulte waqt) aur Android WorkManager (har 15 min, backup_background.dart) dono chalate hain.
/// Sirf Android; koi bhi ghalti app ko nahi rokti.
class InstDueAlert {
  InstDueAlert._();

  static const payload = 'inst_collection';
  static const keyEnabled = 'inst_alert_enabled'; // default on
  static const keyLastDate = 'inst_alert_last_date';
  static const alertHour = 9;
  static const _channelId = 'inst_due_alerts';
  static const _id = 7900;

  static String _dateKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  static String _rs(double v) => 'Rs ${v.round()}';

  /// Notification ka matn (PURE — test). Kuch lena na ho to null (notification nahi).
  static String? bodyFor({
    required int dueTodayCount,
    required double dueToday,
    required int overdueCount,
    required double overdue,
    required List<String> topNames,
  }) {
    if (dueTodayCount == 0 && overdueCount == 0) return null;
    final b = StringBuffer();
    if (dueTodayCount > 0) b.write('Aaj $dueTodayCount qisten (${_rs(dueToday)})');
    if (overdueCount > 0) {
      if (b.isNotEmpty) b.write(' • ');
      b.write('$overdueCount late (${_rs(overdue)})');
    }
    if (topNames.isNotEmpty) b.write('. Pehle: ${topNames.take(4).join(', ')}');
    b.write('. Tap karke wasooli list dekhein.');
    return b.toString();
  }

  static Future<bool> checkAndNotify({DateTime? now, bool force = false}) async {
    if (!DueAlertService.supported) return false;
    try {
      final t = now ?? DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final today = _dateKey(t);
      if (!force) {
        if (prefs.getBool(keyEnabled) == false) return false;
        if (t.hour < alertHour) return false;
        if (prefs.getString(keyLastDate) == today) return false;
      }
      final day = dayStart(t);
      final views = (await InstPlanRepository.instance.list(today: day)).where((v) => v.plan.isActive).toList();
      var dueCount = 0, lateCount = 0;
      double due = 0, late = 0;
      final urgent = <(int, String)>[];
      for (final v in views) {
        final st = v.status;
        if (st.overdue > 0.5) {
          lateCount++;
          late += st.overdue;
          urgent.add((st.daysLate + 1000, v.customerName));
        }
        final todayRem = st.lines.where((l) => l.dueDate == day && l.state != InstallmentState.paid).fold<double>(0, (a, l) => a + l.remaining);
        if (todayRem > 0.5) {
          dueCount++;
          due += todayRem;
          if (st.overdue <= 0.5) urgent.add((0, v.customerName));
        }
      }
      urgent.sort((a, b) => b.$1.compareTo(a.$1));
      final body = bodyFor(
        dueTodayCount: dueCount,
        dueToday: due,
        overdueCount: lateCount,
        overdue: late,
        topNames: [for (final u in urgent) u.$2],
      );
      await prefs.setString(keyLastDate, today); // kuch na ho tab bhi aaj dobara check nahi
      if (body == null) return false;
      await DueAlertService.init();
      await DueAlertService.plugin.show(
        _id,
        'Aaj ki qist wasooli',
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Qist reminders',
            channelDescription: 'Roz subah aaj ki aur late qiston ki yaad dihani',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
        payload: payload,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
