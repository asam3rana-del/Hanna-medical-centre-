/// Hanna Installment license — PUBLIC key (Ed25519). Sirf yeh app mein hai; private key sirf Hanna Solutions ke paas
/// (tools/license_tool.py / tools/license_generator.html). Is se koi nayi key NAHI ban sakti, sirf check hoti hai.
///
/// Key jodi badalni pare (private key gum / leak) to: `license_tool.py genkey` -> naya public key yahan -> nayi build.
/// Us ke baad pehle di hui saari keys bekaar — har dukaan ko nayi key deni hogi.
class LicenseKeys {
  LicenseKeys._();

  static const publicKeyHex = '5416971b40b4205fc2e7428bb3e4e978f986b4bbdcfe640ed4e9952fb289ece6';

  /// Wapas li gayi keys ke serial (refund / chori / ghalat dukaan). Agli app update ke saath lagu hote hain.
  static const revokedSerials = <int>{};
}
