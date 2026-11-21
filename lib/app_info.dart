/// App / developer ki public maloomat — About screen, privacy link, store listing ek hi jagah se.
class AppInfo {
  AppInfo._();

  static const appName = 'Hanna Installment';
  static const developer = 'Asam Hameed';
  static const business = 'Hanna Solutions';
  static const appId = 'com.hannasolutions.installment';
  static const address = 'Ibtisaam Traders, Bhikhi, District Sheikhupura, Pakistan';
  static const supportEmail = 'hannasolutions1@gmail.com';
  static const supportPhone = '03006296815';
  static const supportWhatsAppIntl = '923006296815';

  /// Firebase Hosting (tools/deploy_privacy_site.sh <project-id>). Naya Firebase project banne ke baad agar us ka id
  /// `hanna-installment` nahi to yahan wahi likhein.
  static const privacyPolicyUrl = 'https://hanna-installment.web.app/privacy.html';

  /// App ke andar update check (lib/installment/inst_update.dart, docs/UPDATES.md). Public GitHub repo
  /// `hanna-updates` ki `update.json`. Khali = check band.
  static const updateUrl = 'https://raw.githubusercontent.com/asam3rana-del/hanna-updates/main/update.json';

  /// CI: `--dart-define=APP_BUILD=<run number>`; local / purani build par khali.
  static const build = String.fromEnvironment('APP_BUILD');
}
