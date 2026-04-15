# Privacy Policy

**App:** Labor Day Pay (`com.jj.labordaypay`)
**Effective date:** April 14, 2026 (last updated April 14, 2026)
**Contact:** rowlow302606@gmail.com

**Short version:** Labor Day Pay is a pay calculator. You can use it without signing in. If you choose to sign in with Google, your work records are backed up to your private Google Firebase storage. We don't sell, share, or use your data for advertising. We don't track your location.

## 1. Information We Collect

### 1.1 When you sign in (optional)

Sign-in is optional. If you sign in with Google, we receive from Google:

- Your Google account email address
- Your display name
- Your profile image URL
- A Firebase Authentication user ID

We use this information to identify your account and sync your data across devices.

### 1.2 Work records you create

If you're signed in, the work records you create inside the app are stored in Google Cloud Firestore under your account. These may include:

- Work dates and hours
- Income amounts and calculations you enter
- Country and tax settings you select
- App preferences

If you're not signed in, these records stay only on your device.

### 1.3 Device region (read on-device only)

The app reads your device's language and regional setting (e.g. `en-US`, `ja-JP`) once at launch so it can show the right default currency, tax rules, and public holidays. This reading stays on your device — we do not transmit, store, or log your language or region anywhere.

### 1.4 What we do NOT collect

- Your device's precise or approximate GPS location
- Your contacts, photos, files, or messages
- Advertising IDs
- Analytics about how you use the app beyond what Firebase requires to authenticate you
- Any payment or financial account information

## 2. How We Use Information

- To operate the app's core features
- To sync your work records across your devices when you're signed in
- To protect against abuse (e.g., Firebase authentication security logs)

We do **not** use your information for advertising, profiling, or sale to third parties.

## 3. Third-Party Services

The app uses the following external services, each governed by its own privacy policy:

- **Firebase Authentication** (Google) — for optional sign-in
- **Firebase Firestore** (Google) — for cloud sync of your records when signed in
- **Google Sign-In** (Google) — for sign-in via your Google account
- **Nager.Date public holiday API** (`date.nager.at`) — to fetch public holidays for countries we don't ship hardcoded. The app sends only a two-letter country code (e.g. `DE`, `BR`) and a four-digit year. No account information, device identifiers, or personal data is sent. Results are cached locally so the lookup happens at most once per country per 30 days. See [Nager.Date's service](https://date.nager.at/) for details.

See [Google's Privacy Policy](https://policies.google.com/privacy) for how Google handles data.

We do not use advertising networks, social SDKs, or third-party analytics services.

## 4. Data Retention

- Your cloud-synced records stay in Firebase until you delete them or delete your account.
- Local records on your device are deleted when you uninstall the app.
- To delete your account and all associated cloud data, use the in-app account deletion option, or email us at the address above.

## 5. Your Rights

You can:

- Access, correct, or delete your data from within the app at any time.
- Request a copy or full deletion of your data by emailing us.
- Stop using the app and uninstall it; this removes local data.

Depending on where you live (e.g., EU, UK, California), you may have additional rights under GDPR, UK GDPR, or CCPA, including the right to object to processing or request data portability. Email us to exercise any of these rights.

## 6. Children

This app is intended for a general audience age 13 and older. It is not directed at children under 13. If you believe we've inadvertently collected data from a child under 13, please email us and we'll delete it.

## 7. Security

- All data in transit between your device and our backend is encrypted over HTTPS/TLS.
- Data at rest is encrypted by Google Firebase.
- Sensitive on-device data is stored using Flutter Secure Storage (iOS Keychain / Android EncryptedSharedPreferences).
- Biometric login, if enabled, is handled by your device's operating system and we never see your biometric data.

No method of transmission or storage is 100% secure; we take reasonable measures to protect your data but cannot guarantee absolute security.

## 8. International Data Transfers

Firebase servers may be located in countries different from yours, including the United States. By using the app, you consent to your data being processed in those countries in line with this policy and Google's data handling practices.

## 9. Changes to This Policy

We may update this policy from time to time. Material changes will be noted by updating the "Effective date" above. Continued use of the app after changes means you accept the updated policy.

## 10. Contact

Questions or requests about this policy? Email: rowlow302606@gmail.com
