# Hanna Installment — Play Store listing pack

Package: `com.hannasolutions.installment` · Developer: Asam Hameed (Hanna Solutions) · Category: **Business**
Privacy policy: https://hanna-installment.web.app/privacy.html (`tools/deploy_privacy_site.sh <project-id>`)

## ⚠️ Sab se zaroori: yeh app "loan app" nahi hai
Google Play Pakistan mein personal loan apps se SECP ka license maangta hai. Aisi apps ko contacts aur photos ki
ijazat bhi nahi milti. Hanna Installment kisi ko qarz nahi deti: yeh **dukaandar ka hisaab** hai. Dukaan apne
customers ko saman qiston par bechti hai aur app us ka record rakhti hai. App istemal karne wala dukaandar hai,
qarz lene wala nahi. Reviewer ko yahi saaf nazar aana chahiye:

- Listing, screenshots aur description mein **"loan", "qarz", "credit", "borrow", "lend", "easy cash"** jaise alfaaz NA likhein.
  Likhein: *installment sales record*, *qist hisaab*, *shop bookkeeping*.
- App ke andar koi raqam dene, apply karne ya qarz manzoor karne ka button nahi hai. Aisa kuch kabhi add na karein.
- `READ_CONTACTS` ijazat hata di gayi hai (`tools/android_fix.sh`).
- POS ki "Amanat / Loan" screen aur us ki notification Step 8 mein app se hata di gayi.
- **Financial features declaration** (Play Console > App content):
  - "My app doesn't provide any financial features" chunein, kyun ke app koi financial product (qarz, investment,
    payment, wallet) offer nahi karti. Yeh sirf karobar ka record hai.
  - Agar review ise "Other" maane, to is document ka "Reviewer note" wala hissa bhej dein.
  - Note: yeh mera mashwara hai, qanooni raye nahi. Google aakhri faisla karta hai.

## Store listing

**App name (30):** `Hanna Installment: Qist Hisaab`

**Short description (80):**
`Installment sales record for shops: customers, guarantors, IMEI, receipts`

**Full description (English):**

```
Hanna Installment is a bookkeeping app for shops that sell mobiles, motorcycles, LEDs, fridges, ACs, furniture and other items on installments (qist).

Keep every sale in one place:
• Customer file — name, father's name, CNIC, phone, address, work, with photo and CNIC pictures
• Guarantors — with photo, CNIC and phone, right inside the customer file
• Stock — every piece with its IMEI, serial, engine or chassis number; the same IMEI cannot be entered twice
• Installment plan — cash price, advance, your profit %, number of installments, monthly / 15-day / weekly schedule, rounding
• Collection — record each installment (cash or bank); oldest due is paid first; late-fine suggestion
• Receipts — PDF receipt with customer photo, or a text message on WhatsApp
• Plan statement — A4 PDF with customer and guarantor photos, item numbers, full schedule and signature lines
• Collection list — who to collect from today, this week, or who is late; call or WhatsApp in one tap; share the list with your recovery person
• Defaulters — late customers with their guarantors' phones
• Reports — collection by day, cash / bank, new plans, expected profit, remaining amount by how late it is (1-30, 31-60, 61-90, 90+ days), stock value
• Daily morning notification of today's and late installments
• Cash in / out, expenses, day book, cash register, workers, shop rent and utility bills
• Works offline. Optional cloud sync keeps your phone and PC (Windows) in step, including photos
• Staff logins with roles (admin, manager, cashier); cost and profit hidden from cashiers
• Encrypted backup and restore
• Urdu and English

Hanna Installment is a record-keeping tool for the shop owner. It does not lend money and does not offer any financial product to its users.
```

**Full description (Urdu, second language listing):**

```
Hanna Installment اُن دکانوں کے لیے حساب کی ایپ ہے جو موبائل، موٹر سائیکل، ایل ای ڈی، فریج، اے سی، فرنیچر اور دوسری چیزیں قسطوں پر بیچتی ہیں۔

• کسٹمر کی فائل: نام، والد کا نام، شناختی کارڈ، فون، پتہ، روزگار — تصویر اور کارڈ کی تصویروں کے ساتھ
• ضامن: تصویر، شناختی کارڈ اور فون کے ساتھ
• اسٹاک: ہر پیس اپنے IMEI / سیریل / انجن / چیسس نمبر کے ساتھ — ایک IMEI دو بار درج نہیں ہوتا
• قسط پلان: نقد قیمت، ایڈوانس، منافع %، قسطوں کی تعداد، ماہانہ / 15 دن / ہفتہ وار
• وصولی: ہر قسط کا اندراج (کیش یا بینک)، لیٹ جرمانے کی تجویز
• رسید: کسٹمر کی تصویر والی PDF یا واٹس ایپ میسج
• پلان اسٹیٹمنٹ: ضامن کی تصویروں، IMEI، شیڈول اور دستخط کے ساتھ PDF
• وصولی لسٹ، ڈیفالٹرز (ضامن کے فون کے ساتھ)، رپورٹس
• روز صبح آج کی اور لیٹ قسطوں کی نوٹیفکیشن
• کیش، خرچے، روزنامچہ، ورکرز، کرایہ، بل
• انٹرنیٹ کے بغیر چلتی ہے؛ کلاؤڈ سنک سے موبائل اور کمپیوٹر ایک جیسے
• اسٹاف لاگ اِن، بیک اپ، اردو اور انگریزی

یہ ایپ دکاندار کا حساب رکھتی ہے۔ یہ کسی کو قرض نہیں دیتی۔
```

## Graphics
- **Icon** 512×512 (`assets/images/logo.png` se nahi — Installment ka alag icon behtar: navy background par phone + calendar/check)
- **Feature graphic** 1024×500: "Qist ka poora hisaab — customer, zamin, IMEI, wasooli" + phone screenshot
- **Phone screenshots** (kam az kam 4, 1080×1920 ya 1080×2400) — Demo mode (Settings) mein naqli data daal kar lein,
  kisi asal customer ka CNIC / tasveer screenshot mein NA ho:
  1. Home (aaj ki qisten / late / aaj ki wasooli)
  2. Nayi Qist — summary card (12 × Rs 4,340)
  3. Plan detail — schedule + guarantor tasveerein
  4. Wasooli dialog + WhatsApp receipt
  5. Wasooli List / Defaulters
  6. Customer form (tasveer + CNIC boxes)
  7. Stock list (IMEI ke saath)
  8. Reports
- Windows ke liye: Play par nahi; `Hanna-Installment-windows.zip` seedha dein

## App content (Play Console)

**Privacy policy:** upar wala link.

**Ads:** No ads.

**App access:** Login chahiye. Reviewer ke liye demo account banayein (username / password) aur "Demo mode" on rakhein.
Instructions: "Open app → log in with the demo account → Home shows sample installment plans."

**Target audience:** 18+ only (business tool). "Appeals to children": No.

**Content rating questionnaire:** Category "Utility / Productivity / Business". Violence, sexual content, gambling,
drugs, user-generated sharing ke sawalon ka jawab **No**. Users aapas mein baat nahi karte. Location share nahi hoti.

**News app:** No. **COVID / health:** No. **Government app:** No.

**Financial features:** upar dekhein ("doesn't provide any financial features").

**Foreground service (FOREGROUND_SERVICE_DATA_SYNC):**
- Type: *Data sync → Network transfer: upload / download*.
- Description: "Keeps the shop's records (installment plans, payments, customers) in sync with the shop's other
  devices while the app is open or minimised, so a payment taken on one phone appears on the owner's phone and PC.
  A persistent notification shows while syncing."
- Video (30-60 s): A phone par qist lein → app minimise → B phone par entry aati dikhe, notification bar mein sync ki notification.

**Data safety form:**

| Data type (Play ka naam) | Collected | Shared | Optional? | Purpose |
|---|---|---|---|---|
| Personal info → Name | Yes | No | Required | App functionality |
| Personal info → Phone number | Yes | No | Optional | App functionality |
| Personal info → Address | Yes | No | Optional | App functionality |
| Personal info → Other info (CNIC no., father's name, job) | Yes | No | Optional | App functionality |
| Financial info → Purchase history (items sold on installments) | Yes | No | Required | App functionality |
| Financial info → Other financial info (installments, payments, income estimate) | Yes | No | Required | App functionality |
| Photos and videos → Photos (customer / guarantor / CNIC) | Yes | No | Optional | App functionality |
| App activity → Other actions (audit log of edits) | Yes | No | Required | App functionality, Fraud prevention/security |
| App info and performance → Crash logs | Yes | No | Required | Analytics (sirf jab cloud sync ho; `crash_reports`) |
| Device or other IDs (Firebase anonymous ID) | Yes | No | Required | App functionality, Account management |

- Encrypted in transit: **Yes** (HTTPS / Firestore).
- Users can request deletion: **Yes** (privacy policy section 5: email / WhatsApp, 30 din).
- "Shared": **No**. Firebase (Google) service provider hai jo dukaan ki taraf se data rakhta hai, is liye Play ke qaide mein yeh "sharing" nahi.
- Location, contacts, messages, calendar, health, audio, files: **Not collected**.

## Reviewer note (agar Google sawal kare)
```
Hanna Installment is an offline-first bookkeeping app for shop owners in Pakistan who sell goods (mobile phones,
motorcycles, home appliances) to their own walk-in customers on installment terms. The app user is the shop owner
or shop staff. The app records the shop's own sales, the installment schedule agreed at the counter, and the payments
the shop collects. The app does not lend money, does not facilitate or advertise loans, does not collect loan
applications, does not access the user's contacts, and does not offer any financial product to its users.
Customer and guarantor details (including CNIC pictures) are entered by the shop owner for the shop's own records,
stored on the device and, optionally, in the shop's own Firebase project.
```

## Release checklist
1. Build green (Analyze + Test + Android + Windows)
2. Naya Firebase project + rules + indexes + privacy site deploy
3. Release keystore (POS wala nahi — naya) se signed AAB
4. Play Console: naya app → upar ka sab content → Internal testing (2-3 phones) → Closed testing (personal account par
   12 testers × 14 din ki shart ho sakti hai) → Production
