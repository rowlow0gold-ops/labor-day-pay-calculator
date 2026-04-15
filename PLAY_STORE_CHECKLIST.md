# Google Play Store Publication Checklist
**App:** Labor Day Pay (`com.jj.labordaypay`)
**Last updated:** April 14, 2026

---

## Phase 1 — Assets & Content (do before opening Play Console)

### Done ✅
- [x] **Privacy policy drafted** — `legal/privacy-policy.html` + `.md`
- [x] **Privacy policy hosted** — https://brilliant-genie-347c81.netlify.app/
- [x] **Feature graphic created** — 9 variants (3 designs × EN/KO/JA) in `store-assets/feature-graphics/`
- [x] **Upload keystore created** — saved to Google Drive

### To Do
- [ ] **Re-upload `privacy-policy.html` to Netlify** (current hosted version doesn't disclose Nager.Date API yet)
- [ ] **Pick which feature graphic to ship** (1 minimalist / 2 calendar / 3 bold)
- [ ] **Create 512×512 app icon** (PNG, no alpha, no rounded corners — Play Store applies them)
- [ ] **Verify 27 screenshots** meet Play Store specs:
  - PNG or JPG, 16:9 or 9:16 ratio
  - Min 320 px shorter side, max 3840 px longer side
  - Phone: 2–8 screenshots per language
  - 7-inch tablet: optional but recommended (1–8)
  - 10-inch tablet: optional (1–8)
- [ ] **Write store listing copy** in EN / KO / JA:
  - **App name:** ≤ 30 chars
  - **Short description:** ≤ 80 chars (shows in search results)
  - **Full description:** ≤ 4000 chars (the long one on the listing page)

---

## Phase 2 — Build the AAB

- [ ] **Bump version in `pubspec.yaml`** — `version: 1.0.0+1` (versionName+versionCode). Each Play Store upload needs a higher versionCode.
- [ ] **Confirm `android/key.properties`** points to the keystore on Google Drive (DON'T commit this file — make sure it's in `.gitignore`)
- [ ] **Build release AAB:**
  ```
  flutter clean
  flutter build appbundle --release
  ```
  Output: `build/app/outputs/bundle/release/app-release.aab`
- [ ] **Test the release build** — install via `bundletool` or `flutter install --release` on a real device. Verify sign-in, calendar, sync all work.
- [ ] **Check final size** — should be under 150 MB. Likely ~30–40 MB for this app.

---

## Phase 3 — Play Console Setup

- [ ] **Pay one-time $25 dev registration fee** (skip if already done)
- [ ] **Create new app** in Play Console:
  - App name: Labor Day Pay
  - Default language: English (United States)
  - Free or paid: Free
  - Declare it's an app (not a game)
- [ ] **App access** — declare if any features need login (yes — sign-in is optional, mention it)
- [ ] **Ads** — declare "No, my app does not contain ads"
- [ ] **Content rating questionnaire** — Calculator/utility category, no violence/drugs/etc → IARC: Everyone
- [ ] **Target audience** — age 13+ (matches your privacy policy)
- [ ] **News app** — No
- [ ] **COVID-19 contact tracing** — No
- [ ] **Data safety form** — declare:
  - Collected: Email address, User IDs (linked to user, for app functionality, optional)
  - Shared with third parties: No
  - Encrypted in transit: Yes
  - Users can request deletion: Yes (in-app + email)
  - Third-party SDKs: Firebase Authentication, Firebase Firestore, Nager.Date API
- [ ] **Government apps** — No
- [ ] **Financial features** — No (this is a pay calculator, not a financial transaction app — but you may want to declare "Provides personal financial info" depending on Play's classification; check the help text)

---

## Phase 4 — Main Store Listing

For each language tab (EN, KO, JA), upload:
- [ ] App icon (512×512)
- [ ] Feature graphic (1024×500)
- [ ] Phone screenshots (2–8)
- [ ] App name
- [ ] Short description
- [ ] Full description
- [ ] App category: **Productivity** (or **Tools**)
- [ ] Tags: pay calculator, work hours, holiday pay, payroll
- [ ] Contact email: rowlow302606@gmail.com
- [ ] Privacy policy URL: https://brilliant-genie-347c81.netlify.app/

---

## Phase 5 — Release

- [ ] **Internal testing** — upload AAB, add yourself as tester, install via Play Store testing link, smoke test
- [ ] **Closed testing** *(optional)* — invite a small group via email
- [ ] **Production release:**
  - Choose countries (start with KR, JP, US, CA, AU, DE, BR — countries you support, or "all")
  - Add release notes (per language) — e.g., "Initial release"
  - Submit for review

---

## Phase 6 — Post-submission

- [ ] **Wait for review** — typically 1–7 days for first submission
- [ ] **If rejected** — read the policy violation in Play Console, fix, resubmit
- [ ] **If approved** — app goes live on Play Store. Note the URL: `https://play.google.com/store/apps/details?id=com.jj.labordaypay`
- [ ] **Monitor crash reports** in Play Console → Quality → Android vitals (first 48 hours are critical)
- [ ] **Respond to user reviews** within first week (Play algorithm rewards responsiveness)

---

## Reference: Play Console URLs
- Console: https://play.google.com/console
- Help center: https://support.google.com/googleplay/android-developer
- Policy center: https://play.google.com/about/developer-content-policy/
- Data safety form guide: https://support.google.com/googleplay/android-developer/answer/10787469

---

## Quick stats
- **App package:** com.jj.labordaypay
- **Supported languages:** English, Korean, Japanese
- **Supported countries (hardcoded holidays + tax/currency):** US, KR, JP, CA, AU
- **Other countries:** holidays via Nager.Date API, no tax/currency
- **Privacy policy:** https://brilliant-genie-347c81.netlify.app/
- **Min Android version:** check `android/app/build.gradle` for `minSdkVersion`
- **Target SDK:** must be API 34 (Android 14) or higher as of Aug 2025 — verify this
