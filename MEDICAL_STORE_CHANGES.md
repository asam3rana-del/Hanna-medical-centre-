# Hanna Pharmacy POS — Flutter (branch Raffey)

App ka naam: **Hanna Pharmacy POS** (Android label, iOS, Windows, AppInfo, default shop name).
DB schema v38 -> **v39** (`_onUpgrade`: sirf ADD COLUMN, purana data mehfooz). Migration tests v39 par update.

## Naye features (Kotlin app ke barabar, same Firestore fields)
- Product: **Formula / Generic, Company, Rack** (`genericName`, `company`, `rackLocation`).
- Har search (`matchesQuery`) ab formula aur company se bhi; Sale/Purchase dropdown mein "naam — formula · company · Rack".
- Purchase: har line par **Batch No. + Expiry (MM/YY)** (`purchase_items.batchNo`, `expiry` "yyyy-MM").
  Keyboard: ... Wholesale -> Shopkeeper -> Batch -> Expiry -> Enter = line add (bhari field skip).
  Hold/Recall, adhoora-item draft aur bill edit mein bhi batch/expiry.
- **Medicine & Expiry** screen (`lib/screens/medicine_screen.dart`): Dashboard > Expiry / Formula Search, Reports ka Expiry link.
  Batch-wise expiry (Expired / 30 / 90 din / Sab), cost value (admin/manager), dawai tap = batches + **substitute** (same formula).
- Sale: item chunte hi expired / 30 din mein expire hone wali dawai par laal warning; warna rack number.
- Naye install par units: tablet, capsule, strip, pack, box, bottle, tube, vial, ampoule, sachet.
- Sync: products + purchase items ke naye fields push/pull (purane device ka doc local value nahi mitata).

Batch stock FIFO andaza hai (purani dawai pehle bikti hai) — `lib/utils/medical_expiry.dart`.

## Controlled drugs (℞) register — DB v40
- Product form: "℞ Controlled / parchi wali dawai" switch (`products.controlled`, sync field `controlled`).
- Sale / Quick Sale: bill mein controlled dawai ho to save se pehle Patient*, Doctor*, phone, Parchi No. (`rx_records`, invoice par).
  Cancel = bill save nahi. Credit-limit retry par dobara nahi poochta. Bill edit par purana record pehle se bhara.
- Sync: record sale doc ke `rx` field mein (alag collection / rules ki zaroorat nahi).
- Dashboard "Rx Register" (admin/manager) + Reports "℞ Controlled Drugs Register": Aaj / 7 / 30 din / Sab, search, Share.
- Sale/Purchase dropdown aur Formula search mein "℞ Parchi" nishan.
