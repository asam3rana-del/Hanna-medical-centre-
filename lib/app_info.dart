/// App / developer ki public maloomat — About screen, privacy link, store listing ek hi jagah se.
class AppInfo {
  AppInfo._();

  static const appName = 'Hanna Pharmacy POS';

  /// Hanna Pharmacy POS: kiryana-wale features (Shell Ledger, Shopkeeper rate, Amanat/Loan, Bulk Translate,
  /// Daily Bills, Qist, Wasooli/Collection, Zakat, Cost repair tools) app mein nazar nahi aate. Code / DB / sync jaan boojh kar
  /// barqarar (purana data mehfooz, tests same) — wapas chahiye to sirf ye false karein.
  static const pharmacyMode = true;
  static const developer = 'Asam Hameed';
  static const business = 'Hanna Solutions';
  static const appId = 'com.hannasolutions.pos';
  static const address = 'Ibtisaam Traders, Bhikhi';
  static const supportEmail = 'hannasolutions1@gmail.com';
  static const supportPhone = '03006296815';
  static const supportWhatsAppIntl = '923006296815';

  /// Firebase Hosting (tools/deploy_privacy_site.sh).
  static const privacyPolicyUrl = 'https://my-grocery-pos-8a444.web.app/privacy.html';

  /// CI: `--dart-define=APP_BUILD=<run number>`; local / purani build par khali.
  static const build = String.fromEnvironment('APP_BUILD');
}
