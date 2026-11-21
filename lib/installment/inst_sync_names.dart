/// Hanna Installment sync ke naam (PURE — sync_push_plan / sync_pull_plan isay import karte hain).

const instProfileType = 'inst_profile';
const instGuarantorType = 'inst_guarantor';
const instCategoryType = 'inst_category';
const instItemType = 'inst_item';
const instPlanType = 'inst_plan';
const instPaymentType = 'inst_payment';
const instPhotoType = 'inst_photo';
const instPriceChangeType = 'inst_price_change';
const instSupplierType = 'inst_supplier';
const instPurchaseType = 'inst_purchase';
const instSupplierPaymentType = 'inst_supplier_payment';
const instCashSaleType = 'inst_cash_sale';
const instPurchaseReturnType = 'inst_purchase_return';

/// entityType -> Firestore collection.
const Map<String, String> instPushCollections = {
  instProfileType: 'inst_customer_profiles',
  instGuarantorType: 'inst_guarantors',
  instCategoryType: 'inst_categories',
  instItemType: 'inst_items',
  instPlanType: 'inst_plans',
  instPaymentType: 'inst_payments',
  instPhotoType: 'inst_photos',
  instPriceChangeType: 'inst_price_changes',
  instSupplierType: 'inst_suppliers',
  instPurchaseType: 'inst_purchases',
  instSupplierPaymentType: 'inst_supplier_payments',
  instCashSaleType: 'inst_cash_sales',
  instPurchaseReturnType: 'inst_purchase_returns',
};

/// Pull ki tarteeb = apply ki tarteeb (parent pehle).
const List<String> instPullCollections = [
  'inst_categories',
  'inst_suppliers',
  'inst_purchases', // item se pehle (item -> purchaseServerId)
  'inst_customer_profiles',
  'inst_guarantors',
  'inst_items',
  'inst_plans',
  'inst_payments',
  'inst_cash_sales', // item ke baad
  'inst_purchase_returns', // item + bill ke baad
  'inst_supplier_payments',
  'inst_price_changes',
  'inst_photos', // aakhir mein: owner (customer / guarantor) pehle aa chuka ho
];
