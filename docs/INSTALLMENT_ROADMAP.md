# Hanna Installment — roadmap

Hanna POS (AH-Developer, branch Raffey) ki copy par bana qist (installment) software. Android + Windows (+ iOS).
Naya kaam `lib/installment/` mein; POS ka purana code "Shop tools" se abhi bhi khulta hai.

## Identity (Step 1 — done)
- pubspec name: `hanna_installment` (tests ke `package:` imports bhi)
- App ID: `com.hannasolutions.installment` (Android `tools/android_fix.sh`, iOS `build.yml`)
- App name / window title: Hanna Installment; Windows zip: `Hanna-Installment-windows.zip`
- DB file: `hanna_installment.db` (demo: `hanna_installment_demo.db`) — POS ke data se alag
- Login ke baad home: `InstallmentHomeScreen`
- Firebase: is app ke liye NAYA Firebase project banayein (Settings > Cloud Sync mein us ki google-services.json).
  POS wala project (my-grocery-pos-8a444) is app mein na lagayein.

## Step 2 — done (DB v38)
- `customer_profiles` (1:1 with `customers`): walid ka naam, CNIC (13 hindse, duplicate block), phone 2, pata, rozgar, aamdani
- `inst_guarantors`: zamin (CNIC, phone, rishta, pata). Customer khud apna zamin nahi; ek banda kai logon ka zamin ho to warning
- `inst_categories`: Mobile [IMEI 1, IMEI 2], Motorcycle [Engine, Chassis, Registration], LED, Fridge, AC, Washing Machine, Laptop, Furniture, Other
- `inst_items`: har piece ki row, status in_stock / sold / returned / repossessed; IMEI / serial duplicate block (field ka naam nahi dekhta)
- CNIC / guarantor / cheque ki tasveerein: `KycPhotoStore` (sirf is device par, `kyc_photos/`)
- Tests: `test/installment_models_test.dart`; migration tests mein `_Step(38, ...)`

## Step 3 — done (DB v39)
- Tasveerein form ke andar hi (save se pehle): customer snap + CNIC aage/peeche; guarantor photo + CNIC aage/peeche
  (`inst_photo_widgets.dart` PhotoSlotBox). Guarantor card / plan par guarantor ki gol tasveer (KycAvatar)
- `inst_plans` / `inst_schedule` / `inst_payments`. Hisaab `inst_plan_math.dart` (PURE, test/installment_plan_test.dart):
  baqi = cash − advance; munafa = baqi × % (ya fixed); har qist = kul / n, 10/50/100 tak upar round, farq aakhri qist mein
- Waqfa: mahana (wahi tareekh, chhote mahine mein aakhri din) / 15 din / hafta
- Nayi Qist screen: customer (snap na ho to wahin lein) → zamin chunein (tasveer ke saath) → stock se piece → plan → summary.
  Kaghzat ki kami (photo / CNIC / zamin) par warning. Item `sold` ho jata hai
- Wasooli: pehli qist pehle; late fine ka mashwara (late fee × grace se zyada late qisten − pehle liya fine);
  har wasooli ki `cash_transactions` IN row (reference `inst-pay:<plan>-<pay>`, Day Book mein dikhti hai); WhatsApp receipt
- Plan band: poori adaigi par `completed`; admin/manager "saman wapas" (repossessed); admin "plan delete (ghalti)"
  sirf jab advance ke ilawa koi qist na li ho. Wapas liya piece item form se dobara stock mein
- Home: aaj ki qisten, late, aaj ki wasooli, kul baqi; WhatsApp yaad-dahani

## Step 4 — done (DB change nahi)
- Wasooli List (`inst_collection_screens.dart`): sirf late / aaj (late samet) / 7 din / 30 din; call, WhatsApp,
  poori list share (recovery wale ke liye)
- Defaulters: 1/7/15/30/60/90+ din late; aakhri adaigi; zamin ki tasveer + call + WhatsApp (zamin ko bhi)
- Reports (admin/manager): is mahine / pichhle / is saal / tareekhen — wasooli (qist, advance, fine, cash/bank, roz ka chart),
  naye plan (nakd / qist maliyat, khareed, mutawaqqa munafa), mukammal / wapas, kul baqi aging (1-30/31-60/61-90/90+), stock.
  Hisaab `inst_reports.dart` (PURE, test/installment_reports_test.dart)
- PDF (`inst_pdf.dart`, Urdu POS slips jaisa): plan statement A4 — customer + zamin ki tasveer, CNIC tasveerein, saman ke
  IMEI/serial, schedule, wasooliyan, dastakhat; receipt A5 customer ki tasveer ke saath. Android par seedha customer ki WhatsApp chat
- Yaad-dahani ka text ek jagah (`planReminderText` / `remindPlan`)

## Step 5 — done (DB change nahi)
- Sync (`inst_sync.dart`, naam `inst_sync_names.dart`): 6 Firestore collections — inst_customer_profiles,
  inst_guarantors, inst_categories, inst_items, inst_plans (schedule plan ke andar), inst_payments.
  Har write ke saath usi transaction mein queue; references serverId se (local ids har device par alag).
  Category id naam se (`inst_category:mobile`) — har device ki pehle se bani "Mobile" ek hi doc.
  Pull apply POS ke `applyRestOfServerChanges` ke aakhir mein; anpushed local edit purani cloud copy se nahi badalti.
  Wasooli ki cash row POS ke cash_transactions sync se; payment `cashServerId` se judti hai.
  Doosre device ki payment hatane par cash row `cashTxId` se bhi hat'ti hai.
  "Force full push" (resyncAllLocalData) qist data bhi bhejta hai. Test: test/installment_sync_test.dart
- Plan number mein device tag ke 2 harf (`Q-7F0012`) — do devices ke number na takrayein
- Rules (firestore*.rules + deploy_rules_live.sh), indexes (branchId+updatedAt / branchId+pushedAt har collection),
  functions/src/syncLogic.ts (cashier: profile/zamin/saman/plan/wasooli upsert) — sab mein 6 collections
- Deploy scripts mein project ka naam ab lazmi; POS ka project (my-grocery-pos-8a444) dene par ruk jate hain
- Roz subah 9 ke baad notification (`inst_due_alert.dart`): aaj ki / late qisten + naam; tap = Wasooli List
- Shop tools ab saaf list (`inst_shop_tools_screen.dart`): cash, kharche, day book, register, workers, kiraya, bills,
  backup, users, recycle bin. Purana POS dashboard sirf admin ke liye "Advanced" mein

## Firebase setup (naya project, ek dafa)
1. console.firebase.google.com par naya project (maslan `hanna-installment`), Firestore (production mode), Authentication > Anonymous ON
2. Android app add: package `com.hannasolutions.installment`, google-services.json download
3. App: Settings > Cloud Sync Setup mein google-services.json + branch code; device ka UID `branch_members/{uid}` mein (`branchId`)
4. Rules: `bash deploy_rules_live.sh roles <project-id>`; indexes: `bash deploy_indexes.sh <project-id>`
   (ya Console mein firebase/firestore.rules paste + indexes haath se)

## Step 6 — done
- Tasveeron ka sync Storage ke baghair (`inst_photo_sync.dart`): har tasveer ek `inst_photos` document mein base64 JPEG
  (doc id `inst_photo:<c|g>|<ownerServerId>|<kind>`). Customer chehra (PartyPhotoStore, kind `face`), CNIC aage/peeche,
  cheque, guarantor ki tasveer. CNIC tasveer ab 1100px q75. 600 KB se bari file upload nahi hoti.
  Stores ka `onLocalChange` -> queue; pull par `saveBytes` (dobara upload nahi); wahi size ho to dobara nahi likhti.
  Guarantor delete: pehle tasveerein (cloud tombstone), phir guarantor. "Force full push" ke baad sab tasveerein bhi
  (`SyncQueueHelper.afterResync`). Rules / indexes / functions mein `inst_photos` (function payload limit is type ke liye 1,000,000)
- Privacy policy (`tools/deploy_privacy_site.sh <project-id>`) Installment ke liye: CNIC, zamin, tasveerein, IMEI, sync
  mein tasveerein. `AppInfo.privacyPolicyUrl` = https://hanna-installment.web.app/privacy.html (project id alag ho to badlein)

## Step 7 — done
- `docs/PLAY_STORE_LISTING.md`: naam / short / full description (English + Urdu), graphics + screenshots list,
  Data safety jadwal, content rating, foreground service declaration, Financial features declaration ka mashwara,
  reviewer note, release checklist. Asal nukta: app "loan app" nahi — listing mein loan / qarz / credit alfaaz nahi
- `READ_CONTACTS` hataya (`tools/android_fix.sh`, `tools:node="remove"` bhi) — Pakistan mein loan apps ko contacts mana

## Pehli green build — 2026-11-13 (repo asam3rana-del/Hanna-Installment, branch Raffey)
- Analyze + saare tests paas; app phone par chal gayi. Ek test fix: installment_sync_test mein `singleInstance: false`
  (warna dono `:memory:` ek hi DB)

## Step 8 — done: grocery screens ka safaya
- 57 UI files mitai (sale, purchase, items/product, stock (adjust/taking/audit/report/rebuild), rate tools, bulk translate,
  bill scan, party dashboard/ledger, POS reports/balance sheet/monthly, history, receivables, shell ledger, setup guide,
  purana POS dashboard, Amanat/Loan, POS udhaar wasooli (collection hub / queue / due reminders / payments)) + services/collection_actions
- Raste band: Settings se Parties/Items/Reports/Sale/Purchase/Shell Ledger/Setup guide; POS ki Sale + credit-limit settings
  `_posFeatures = false` ke peeche; Day Book se bill nahi khulta; customer screen se POS "Ledger" hata; Shop tools se "Advanced"
- POS udhaar (DueAlertService.checkAndNotify) aur Amanat/Loan (ReturnAlertService) notifications band; qist + bills + backup chalti
- Crash dialog (pichhli crash ka log / developer ko bhejna) ab Installment Home par
- DB / sync / repositories / helper code NAHI hataya — sync engine aur tests un par chalte hain; app mein nazar nahi aate
- `import-zip.yml`: zip mein `.import-delete.txt` ho to us ki files repo se mitata hai (rsync khud nahi mitata).
  Workflow file bot update nahi kar sakta — user ne haath se paste ki

## Step 9 — done (DB v40)
- Munafa (Reports, admin/manager): har wasooli mein munafe ka hissa = raqam × (qist qeemat − khareed) ÷ qist qeemat
  ("installment method"; gol aakhir mein) + late fine − kharche (expenses table: salary / kiraya / bills samet, category wise)
  = khalis munafa. Khareed na likhi ho to us wasooli ka munafa nahi ginta (alag batata hai). Plan screen: munafa ab tak / kul.
  `profitShare` / `profitReport` PURE (test/installment_reports_test.dart)
- Rate badlein (Stock screen ka 💲 button, admin/manager): category + search se pieces, ±% / ±Rs / naya rate, gol karna,
  "khareed bhi badlein" (default band), preview + stock maliyat ka farq. Sirf in_stock; bane plan nahi badalte.
  `inst_price_changes` table (v40) + sync (`inst_price_change`, sirf admin/manager functions mein); item form par "Rate history";
  form se qeemat badlo to bhi record. Reports > Stock: naqd qeemat par maliyat, stock mein munafa, muddat ki rate tabdeeliyan

## Step 10 — done: License (Trial / Annual) — tafseel docs/LICENSING.md
- `lib/license/`: Ed25519 dastakhat wali offline keys (cryptography package, nayi dependency nahi), device code se bandhi,
  tareekh peeche karne ki pakar, expiry par sirf dekhna + backup (writes band), Demo dukaan bina license,
  LicenseGate (main + login ke baad), Home par patti, Settings > License. Test: test/license_test.dart (Python tool ke vectors)
- Key banane ke tools: `tools/license_tool.py` (pure Python) aur `tools/license_generator.html` (phone, offline) —
  Python / JS / Node crypto se bit-by-bit milaye gaye
- build.yml: Android + Windows `--obfuscate --split-debug-info` (symbols artifact). `.gitignore`: *.key, licenses.csv

## App icon — done
- `branding/`: Hanna logo (Android adaptive + legacy, iOS 1024, Windows .ico, Play 512, PDF logo `assets/images/logo.png`).
  Android: `tools/android_fix.sh` copy karta hai; iOS / Windows: build.yml ke "Set ... app icon" steps

## Step 11 — done (DB v41): Khareed (Purchase)
- Home > Khareed (admin/manager): bill list (is mahine ki khareed, suppliers ko kul dena), naya bill = supplier + bill no. +
  tareekh + kai pieces (har piece stock mein, IMEI duplicate check, "ek aur aisa" copy) + abhi di gayi raqam (cash / bank)
- Bill detail: pieces (tap = item form), adaigiyan, Pay, edit (no. / tareekh / note), delete (sirf jab saare pieces stock mein)
- Suppliers: list + baqi, khata (purana baqi, bill +, adaigi −, running balance), Pay, naya bill; adaigi long-press = wapas
- Har adaigi = `cash_transactions` OUT (`inst-supp:<id>`). Bill total = pieces ki khareed qeemat (baad ka rate badalna bill nahi badalta)
- Tables: `inst_suppliers`, `inst_purchases`, `inst_supplier_payments`, `inst_items.purchaseId`. Sync: 3 nayi collections
  (rules / indexes / functions updated — har dukaan ke Firebase par rules + indexes dobara deploy). Reports > Khareed
- Tests: installment_purchase_test (khata), installment_sync_test (A -> B purchase), migration v41

## Step 12 — done (DB change nahi): Reports hub
- Home > Reports ab hub (`inst_report_screens.dart`): Karobar ki surat (customers se lena / is mein late / 7 din ki qisten /
  stock lagat par / suppliers ko dena / khalis) + 8 reports: Munafa & Wasooli (purani), Sale, Stock, Aane wali qisten,
  Late (Defaulters 1+ din), Lena (customer wise), Dena (suppliers), Khareed. Har nayi report WhatsApp / share text
- Sale: muddat ke plan, nakd / qist maliyat, advance, khareed, mutawaqqa munafa (khareed na ho to alag ginti), category wise
- Stock: category wise, kitna purana (0-30 / 31-90 / 91-180 / 180+ din), purane pehle list
- Qisten: aaj / 7 din / is mahine / agle mahine / tareekhen, purani late bhi (switch), din wise jor
- Lena: customer wise baqi, late raqam + din, agli qist; sirf late ka filter
- Hisaab PURE `inst_ledger_reports.dart` (test/installment_ledger_reports_test.dart)

## Step 13 — done (DB v42): Naqd (cash) sale
- Home > Naqd Sale (sab users): stock se piece dhoondo (model / IMEI), qeemat (naqd qeemat pehle se), cash / bank,
  customer ka naam / phone (ikhtiyari) -> piece `sold`, `cash_transactions` IN (`inst-sale:<id>`), number `N-<tag><id>`.
  Raseed WhatsApp / share. Admin / Manager "wapas": piece dobara stock, cash row hat'ti hai.
  Item form: stock piece par "Naqd bechein"; bike piece par "Plan / sale dekhein"
- `inst_cash_sales` (bechte waqt ki khareed qeemat ke saath). Sync `inst_cash_sale` (cashier bhi; rules / indexes / functions)
- Munafa: naqd sale ka munafa (qeemat − khareed) gross profit mein; Sale Report: qist + naqd ek saath (alag ginti)
- Tests: profit (cash sales), ledger (cashSaleRows), sync (A -> B), migration v42

## Step 14 — done (DB v43)
- Supplier ko wapsi: bill > "Wapas karein" (stock wale pieces chunein) -> piece `returned`, supplier ka baqi kam
  (`inst_purchase_returns`, raqam = khareed). Bill / khata mein wapsi; "wapsi khatam" = piece dobara stock. Sync `inst_purchase_return`
- Purane bill mein piece: bill > "Piece shamil karein" (bill ki raqam barhti hai)
- Reports ki PDF (`InstPdf.shareTable`, A4 jadwal, Urdu): Sale, Stock, Aane wali qisten, Lena, Supplier khata
- Naqd sale ka customer: customer list se chunein (`inst_cash_sales.customerId`, sync `customerServerId`);
  customer ke page par "Naqd khareedari"
- Karobar ki surat: haath mein cash + bank (cash_transactions IN − OUT) bhi; khalis = lena + stock + cash + bank − dena

## Step 15 — done (DB v44)
- Naqd sale ki wapsi: sale > "Sale wapsi" -> kitne wapas diye (0..qeemat), cash/bank, wajah -> piece stock mein,
  refund cash OUT (`inst-sret:<id>`); sale record rehta hai (returnedAt / refund / returnNote / refundCashTxId, sync).
  Munafa: kati hui raqam (qeemat − refund). "Ghalat entry delete" alag (sab mita deta hai)
- Dashboard: "Pay / Receive" (lena / dena / wapsi): qist wasooli, naqd sale, cash in, supplier, kharcha, cash out,
  sale wapsi, khareed wapsi, qist ka saman wapas. Zakat Settings se hata
- License: device code ab secure storage (backup password wale options) + prefs — har dafa naya code wala bug khatam

## Step 16 — done (DB change nahi): poori adaigi par discount
- Wasooli dialog (Admin / Manager): "Poora hisaab" tick -> Discount likho, raqam = baqi − discount khud. Discount alag
  payment (kind `discount`, cash row nahi): baqi kam, plan mukammal; wasooli / cash / aaj ki wasooli mein nahi ginti.
  Munafa: −discount × (khareed / qist qeemat) (yani asal = (qist − discount) − khareed). Reports mein "Rayat di"
- Plan screen par discount ki line (🏷), raseed / PDF mein "Discount"; hata bhi sakte hain (Admin / Manager)

## Step 17 — done (DB change nahi): qisten badalna (reschedule)
- Plan menu (Admin / Manager) -> "Qisten tabdeel": ada hissa wahi (aadhi ada qist tootti hai), baqi + izafi charge
  (ikhtiyari, munafa mein) nayi ginti / waqfe / pehli tareekh se. Dialog mein naya schedule preview. Plan note mein record.
- Plan ki count / frequency / firstDueDate / installmentTotal / totalPrice / profit update; schedule sync ke saath jata hai.

## Step 18 — done (DB v45): customer blacklist
- `customer_profiles.blockedReason / blockedAt`. Customer detail (Admin / Manager) -> block icon: wajah likho; laal banner,
  list mein "Blacklist" badge. Sync hota hai. Profile edit karne se block nahi hat'ta.
- Naya qist plan: blacklist ya pehle saman wapas liya gaya ho to warning; blacklist customer ka plan sirf Admin / Manager.

## Step 19 — done (DB / naya package nahi): scanner se sale
- Dashboard: "Scan se Sale" tile + upar scanner icon. Camera se IMEI / serial / engine no. ki tasveer -> ML Kit text
  (phone par hi, pehle se app mein) -> stock ka piece -> "Naqd sale" ya "Qist par". Bika hua piece: tafseel.
- PC / mobile: USB / Bluetooth barcode scanner (keyboard jaisa) ya haath se number likh kar Enter.
- Live barcode (Step 19b): `mobile_scanner` (Android CameraX + ML Kit, iOS). Dabbe ke kai barcode mein se jo stock se
  mile wahi; baqi par "stock mein nahi" likh kar scan jari. Torch button. Windows par button chhupa (scanner gun chalti hai).
- import-zip.yml: pubspec.yaml badle to pubspec.lock khud `flutter pub get` se bana kar commit.

## Step 20 — done: iqrar nama ki sharait + privacy site
- Shop tools -> "Iqrar nama ki sharait" (Admin / Manager): dukaan ki sharait (har line ek shart, Urdu / English namuna).
  Plan ki PDF mein dastakhat se pehle "Sharait / Iqrar nama" + "humne sharait parh kar qubool kin". Har device par alag.
- Privacy policy site: `web_installment/` (index + privacy, camera scanning ki line samet). Deploy: Actions ->
  Deploy Firebase -> what = privacy (service account ko "Firebase Hosting Admin" role) -> https://<project>.web.app/privacy.html

## Step 21 — done (DB v46): security cheque / kaghzat
- `inst_securities` (plan ke doc mein `securities` list ke saath sync, alag collection / rules nahi). Plan detail ->
  "Zamanat": cheque (number, bank, raqam) / stamp paper / doosra kaghaz; tap -> wapas diya / hatao. Plan band aur kaghaz
  paas ho to peeli patti. Dashboard "Cheque aur kaghzat": sab paas pare, band plan wale upar. Plan PDF mein bhi.

## Step 22 — done: sab ko ek saath yaad-dahani
- Dashboard "Yaad dahani bhejein": aaj + late / kal tak / 3 din. "Agla bhejein" har dafa agle customer ki WhatsApp chat
  (message tayyar). Aaj kis ko bhej diya, isi device par yaad (har din naya).

## Step 23 — done: zamin ki jaanch
- Naya plan save par: zamin ka CNIC kisi blacklist customer / saman-wapas customer ka ho, ya woh pehle kisi saman-wapas
  plan ka zamin raha ho => warning (customer ki warning ke saath).

## Step 24 — done: saman badalna (exchange)
- Plan menu -> "Saman badlein": stock se naya piece (search), qeemat ka farq (+/-), baqi ki qisten, preview. Ada raqam
  wahi; purana piece `returned` (check kar ke dobara stock), naya `sold`; khareed qeemat / munafa / plan note update.

## Step 25 — done: Excel export
- Har report ka PDF button ab poochta hai: PDF ya Excel (CSV, UTF-8 BOM, raqam number ki shakal mein, formula se hifazat).

## Step 26 — done: dashboard chart (Admin / Manager)
- Pichhle 6 mahine: sale (plan + naqd), wasooli, munafa — bar chart, mahine par tap = us ki raqam.

## Step 30 — done (DB v47): dukaan ki farmaishein
- Dashboard: search bar (naam / CNIC / phone / khata no.) -> customer. 8 tiles + "More" (baqi sab neeche sheet mein).
- Customer: "Register khata no." (CNIC ke baad, `customer_profiles.khataNo`, sync, search). Customer screen par history
  card: jari / mukammal / wapas / late plans, kul khareeda / diya / baqi — ek bande ke sab plans ek jagah.
- Naya qist form: sirf "qist par sale price" (munafa = sale − khareed); upar Qist / Naqd toggle (Naqd = cash sale).
- Qist: rozana (daily, 400 tak). Qist lete waqt "wasooli ki tareekh". Schedule ki qist par tap (Admin / Manager) =
  tareekh badlo, chahein to baad wali bhi utne din khiskao.
- Receipt (PDF + text + naqd sale) hamesha English.
- Purchase: "Yahi model dobara (sirf naya IMEI)" + "Yahi model: kai dabbe scan" (model / rate aakhri piece wala).

## Step 31 — done (DB change nahi)
- Munafa sirf Reports mein (`kShowProfitOutsideReports = false`): naya plan / plan / naqd sale / item par nahi.
- Scan (sale + purchase) chhupa (`kShowScan = false`), code mojood.
- Dashboard search: customer + saman (model / IMEI) — stock mein kitne, rate (naqd qeemat), status.
- Lena / Dena saada: qist wasooli, "doosri raqam aayi", supplier ko, "kharcha / raqam gayi" (ek dialog), cash book.
- Dashboard: "Returns" tile (sale / qist saman / purchase wapsi + history); Admin / Manager ko "Lena hai" / "Dena hai".
- Reports: Purchase History, Returns History (PDF / Excel).
- Dukaan ka logo (Settings > Shop Information) PDF par; dukaan ka naam ho to receipt / PDF par app ka naam / logo nahi.

## Step 32 — done (DB change nahi)
- Dashboard: sab se upar Lena / Dena (raqam chhupi, aankh dabakar), phir search, phir aaj / late / wasooli. Customers /
  stock / stock cost aur "zamin nahi" wali patti hata di. "Wasooli" tile (sab jin se lena hai); Reports -> Settings.
- Wasooli list: naya pehla option "Sab jin se lena hai" (kul baqi), default.
- Kharche: category nahi (sab Miscellaneous + tafseel).
- Naya qist: tasdeeq ki jagah iqrar nama screen — khulasa + sharait + customer / zamin ke dastakhat (ungli / stylus,
  bina package). Dastakhat KycPhotoStore owner 'p' (plan) mein, sync, plan PDF mein dastakhat ki lakeer ke upar.

## Abhi baqi
- Feature graphic (Play Store)
