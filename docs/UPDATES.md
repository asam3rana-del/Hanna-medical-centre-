# Door ke customers ko update (app ke andar)

App har 6 ghante mein ek dafa (internet ho to) ek public file dekhti hai:
`https://raw.githubusercontent.com/asam3rana-del/hanna-updates/main/update.json` (`AppInfo.updateUrl`).
Wahan naya build ho to Home par "Naya update aa gaya hai" — Download dabane par browser APK utaarta hai, phir
Android "Update" poochta hai. Purani app ke upar install = data aur license wahi. Shop tools > "Update check karein"
se haath se bhi.

## Ek dafa (setup)
1. GitHub par **naya PUBLIC repo**: naam `hanna-updates` (Add a README tick).
   Is mein sirf update.json aur APK — koi code, key ya password nahi.
2. Repo mein `update.json` banayein (namuna: `tools/update.json.example`).

## Har naye update par
1. Hanna-Installment repo mein Build green -> Actions -> us run ka number (maslan #31) yaad rakhein.
   Artifacts se `android-apk` (aur `windows-build`) download karein, zip khol kar `app-release.apk` nikalein.
2. `hanna-updates` repo -> **Releases** -> "Create a new release" -> Tag: `build-31` ->
   `app-release.apk` (aur `Hanna-Installment-windows.zip`) drag karein -> **Publish release**.
3. `update.json` edit karein: `build` = 31, `version`, `url` = release ka link
   (`https://github.com/asam3rana-del/hanna-updates/releases/download/build-31/app-release.apk`), `notes` = kya naya hai.
   Commit. 6 ghante ke andar sab customers ko dialog aa jata hai (ya woh khud "Update check karein" dabayein).

## Zaroori update
`"min_build": 31` likhein to 31 se purani app par dialog band nahi hota (sirf Download). Aam taur par 0 rakhein.

## Hifazat
- Sirf `https://` link chalta hai.
- Android sirf usi keystore se sign hui APK ko update maanta hai — koi ghalat link de bhi de to install nahi hogi.
- `build` hamesha CI ka run number (app mein `--dart-define=APP_BUILD`, build.yml). Local build (0) par auto check band.
