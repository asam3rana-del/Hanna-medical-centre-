# Hanna Installment — License (Trial / Annual)

## Kaise kaam karta hai
- Har phone / PC ka apna **Device Code** (License screen par, `ABCD-EFGH-JKMN-PQRS`). Key isi code ke liye banti hai —
  ek device ki key doosre par "This key is for another device".
- Key **Ed25519** (digital signature) se sign hoti hai. Private key sirf Hanna Solutions ke paas; app mein sirf public key
  (`lib/license/license_keys.dart`). App khol kar / code dekh kar bhi nayi key nahi ban sakti; key ka ek harf badlo to ghalat.
- Internet ki zaroorat nahi (offline check).
- **Trial**: 1-60 din (aaj samet). **Annual**: kisi bhi aakhri tareekh tak (us din ke aakhir tak chalti hai).
- Expiry se 15 din pehle Home par peeli patti. Khatam hone par: data dekh sakte hain, backup le sakte hain; naya customer /
  zamin / saman / rate / qist plan / wasooli band (`LicenseService.requireWritable`). Data kabhi nahi mitta.
- Phone ki tareekh peeche ki (aakhri dekhi tareekh se 1 din se zyada, ya key ke issue din se pehle) → "tareekh ghalat",
  sirf dekhna. Tareekh theek karein to theek. Ghalti se tareekh aage chali gayi thi aur ab app ruk gayi: **nayi serial
  ki key** de dein (us se reset hota hai). Wahi purani key dobara dalne se reset NAHI hota.
- Kabhi sahi key na lagi ho → app sirf License screen dikhati hai (+ "Demo dukaan" — alag practice DB, Play reviewer ke liye).
- Release build `--obfuscate` (APK / EXE mein naam mit jate hain); crash symbols artifact `android-debug-info`.

## Key banana
**Phone par (aasaan):** `tools/license_generator.html` Chrome mein kholein (internet band behtar) → private key ki 64-harf
line paste → customer ka Device Code → Trial (din) ya Annual (aakhri din) → Serial (agla number) → "Key banayein" →
Copy → customer ko WhatsApp. "Copy record line" apni list (licenses.csv / Google Sheet) mein rakhein.
Page par neeche "Public key" dikhti hai — `license_keys.dart` wali se milni chahiye (warna ghalat private key).

**PC / Termux:**
```
python3 tools/license_tool.py issue --key hanna-license-private.key --device ABCD-EFGH-JKMN-PQRS --type trial --days 15 --customer "Ali Mobiles"
python3 tools/license_tool.py issue --key hanna-license-private.key --device ABCD-EFGH-JKMN-PQRS --type annual --until 2027-11-30
```
Serial khud agla lagta hai aur `licenses.csv` mein record banta hai.

## Customer ka tareeqa
App kholein → License screen → "Send on WhatsApp" (Device Code aap ko aata hai) → aap key bhejte hain → "Activate".
Renew: Settings → License → nayi key paste → Activate (purana data wahi rehta hai).

## Zaroori
- **Private key** (`hanna-license-private.key`) ka backup 2 jagah (Drive + USB). Gum = nayi key nahi ban sakti; leak = koi bhi
  key bana sakta hai → `license_tool.py genkey` se nayi jodi, naya public key `license_keys.dart` mein, nayi build, sab ko nayi key.
- Private key / licenses.csv kabhi repo, Project ya chat mein na daalein (`.gitignore` mein `*.key`, `licenses.csv`).
- Key wapas leni ho (refund / chori): serial `LicenseKeys.revokedSerials` mein daal kar nayi build (update ke baad band).
- App uninstall / "Clear data" / naya phone = naya Device Code → nayi key (purani serial revoke kar sakte hain).
- Hadd: koi rooted phone par app ka code badal de (patch) to koi bhi offline license rok nahi sakta — obfuscation is ko
  mushkil banata hai, na-mumkin nahi. Aage chal kar: online check (Firestore / Cloud Function) mazeed hifazat de sakta hai.
