import 'package:flutter/material.dart';

import '../screens/about_screen.dart';
import '../screens/backup_export_screen.dart';
import '../screens/cash_register_screen.dart';
import '../screens/cash_screen.dart';
import '../screens/day_book_screen.dart';
import '../screens/expense_screen.dart';
import '../screens/recycle_bin_screen.dart';
import '../screens/shop_rent_screen.dart';
import '../screens/user_management_screen.dart';
import '../screens/utility_bills_screen.dart';
import '../screens/workers_screen.dart';
import '../services/session.dart';
import '../theme/theme_manager.dart';
import '../utils/loc.dart';
import 'inst_ui.dart';
import 'inst_terms.dart';
import 'inst_update.dart';

/// Step 5: POS ki sirf woh screens jo qist ki dukaan ko chahiye (cash, kharche, day book, workers, kiraya,
/// bills, backup, users). Grocery wali (sale / purchase / units / bill scan / rate list...) yahan nahi.
/// Purana POS dashboard aur grocery screens app se hata diye gaye (Step 8).
class InstShopToolsScreen extends StatelessWidget {
  const InstShopToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ThemeManager.palette;
    final mgr = Session.isAdminOrManager;
    final admin = Session.isAdmin;
    final rows = <(IconData, String, String, Color, Widget Function())>[
      (Icons.swap_vert, Loc.t('Cash In / Out', 'کیش ان / آؤٹ'), Loc.t('Other money in and out', 'باقی رقم کا آنا جانا'), p.teal, () => const CashScreen()),
      (Icons.receipt_long_outlined, Loc.t('Expenses', 'خرچے'), Loc.t('Shop expenses', 'دکان کے خرچے'), p.red, () => const ExpenseScreen()),
      (Icons.menu_book_outlined, Loc.t('Day Book', 'روزنامچہ'), Loc.t('Everything of the day', 'دن بھر کا حساب'), p.navy, () => const DayBookScreen()),
      (Icons.point_of_sale_outlined, Loc.t('Cash Register', 'کیش رجسٹر'), Loc.t('Open / close the till', 'گلہ کھولیں / بند کریں'), p.amber, () => const CashRegisterScreen()),
      if (mgr) (Icons.badge_outlined, Loc.t('Workers', 'ورکرز'), Loc.t('Salary, advance, leave', 'تنخواہ، ایڈوانس، چھٹی'), p.purple, () => const WorkersScreen()),
      if (mgr) (Icons.store_mall_directory_outlined, Loc.t('Shop Rent', 'دکان کا کرایہ'), Loc.t('Monthly rent', 'ماہانہ کرایہ'), p.orange, () => const ShopRentScreen()),
      if (mgr) (Icons.bolt_outlined, Loc.t('Utility Bills', 'بل'), Loc.t('Electricity, gas, internet', 'بجلی، گیس، انٹرنیٹ'), p.blue, () => const UtilityBillsScreen()),
      if (mgr) (Icons.gavel_outlined, Loc.t('Agreement terms', 'اقرار نامہ کی شرائط'), Loc.t('Printed on plan PDF', 'پلان کی PDF پر چھپیں'), p.navy, () => const InstTermsScreen()),
      if (admin) (Icons.backup_outlined, Loc.t('Backup / Restore', 'بیک اپ'), Loc.t('Save your data', 'ڈیٹا محفوظ کریں'), p.teal, () => const BackupExportScreen()),
      if (admin) (Icons.manage_accounts_outlined, Loc.t('Users', 'یوزرز'), Loc.t('Staff login and roles', 'اسٹاف لاگ اِن'), p.navyLight, () => const UserManagementScreen()),
      if (admin) (Icons.restore_from_trash_outlined, Loc.t('Recycle Bin', 'ری سائیکل بن'), Loc.t('Deleted records', 'حذف شدہ ریکارڈ'), p.textMuted, () => const RecycleBinScreen()),
      (Icons.info_outline, Loc.t('About', 'ایپ کے بارے میں'), Loc.t('Version and support', 'ورژن اور رابطہ'), p.textMuted, () => const AboutScreen()),
    ];
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        instHeader(context, p, Loc.t('Shop tools', 'دکان کے ٹولز'), Loc.t('Cash, expenses, staff, backup', 'کیش، خرچے، اسٹاف، بیک اپ')),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
            for (final (icon, title, sub, color, open) in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: instCard(p),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: color.withOpacity(0.13), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: color),
                  ),
                  title: Text(title, style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                  subtitle: Text(sub, style: TextStyle(color: p.textMuted, fontSize: 12)),
                  trailing: Icon(Icons.chevron_right, color: p.textMuted),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => open())),
                ),
              ),
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: instCard(p),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: p.teal.withOpacity(0.13), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.system_update, color: p.teal),
                ),
                title: Text(Loc.t('Check for update', 'اپڈیٹ چیک کریں'), style: TextStyle(color: p.textDark, fontWeight: FontWeight.bold)),
                subtitle: Text(
                    InstUpdate.currentBuild > 0
                        ? Loc.t('This app: build ${InstUpdate.currentBuild}', 'یہ ایپ: build ${InstUpdate.currentBuild}')
                        : Loc.t('Get the newest version', 'نیا ورژن حاصل کریں'),
                    style: TextStyle(color: p.textMuted, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: p.textMuted),
                onTap: () => InstUpdate.checkNow(context),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
