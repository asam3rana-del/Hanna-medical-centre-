# Hanna Medical Store — Flutter (branch Raffey)

App ka naam: **Hanna Medical Store** (Android label, iOS, Windows, AppInfo, default shop name).
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
