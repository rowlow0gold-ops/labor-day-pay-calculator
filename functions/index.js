const functions = require("firebase-functions");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

admin.initializeApp();
const db = admin.firestore();

/**
 * Scheduled Cloud Function: runs daily at 06:00 UTC
 * Checks official tax data sources and updates Firestore if changed.
 *
 * To deploy:
 *   1. cd functions && npm install
 *   2. firebase deploy --only functions
 *
 * NOTE: Scheduled functions require Firebase Blaze (pay-as-you-go) plan.
 * For Spark (free) plan, you can trigger manually via HTTP instead.
 */

// ── Scheduled version (Blaze plan required) ──
exports.dailyTaxUpdate = functions.pubsub
  .schedule("every day 06:00")
  .timeZone("Asia/Seoul")
  .onRun(async (context) => {
    console.log("Running daily tax rate update...");
    await updateAllCountries();
    return null;
  });

// ── HTTP trigger version (works on Spark free plan) ──
exports.triggerTaxUpdate = functions.https.onRequest(async (req, res) => {
  try {
    await updateAllCountries();
    res.json({ success: true, message: "Tax rates updated" });
  } catch (error) {
    console.error("Update failed:", error);
    res.status(500).json({ success: false, error: error.message });
  }
});

async function updateAllCountries() {
  const countries = ["kr"];

  for (const code of countries) {
    try {
      const updates = await fetchTaxData(code);
      if (updates && Object.keys(updates).length > 0) {
        updates.lastUpdated = admin.firestore.FieldValue.serverTimestamp();
        await db.collection("tax_rates").doc(code).set(updates, { merge: true });
        console.log(`Updated ${code} tax data`);
      }
    } catch (error) {
      console.error(`Failed to update ${code}:`, error.message);
    }
  }
}

/**
 * Fetch tax data for a country.
 *
 * Currently returns hardcoded 2025/2026 data.
 * TODO: Connect to official APIs when available:
 *   - Korea: 국세청 OpenAPI (https://www.nts.go.kr)
 *   - Japan: 国税庁 (https://www.nta.go.jp)
 *   - US: IRS (https://www.irs.gov)
 *   - etc.
 *
 * The structure is designed so when APIs become available,
 * you just update the fetch logic here — the app doesn't change.
 */
async function fetchTaxData(countryCode) {
  switch (countryCode) {
    case "kr":
      return getKoreaData();
    default:
      return null;
  }
}

// ── Korea ──
function getKoreaData() {
  return {
    dailyWorkerFlatTax: 0.033, // 3.3%
    insurance: {
      nationalPension: 0.045,     // 국민연금 4.5%
      healthInsurance: 0.03545,   // 건강보험 3.545%
      longTermCare: 0.004541,     // 장기요양 0.4541% of gross
      employmentInsurance: 0.009, // 고용보험 0.9%
    },
    incomeTaxBrackets: [
      { min: 0, max: 14000000, rate: 0.06 },
      { min: 14000000, max: 50000000, rate: 0.15 },
      { min: 50000000, max: 88000000, rate: 0.24 },
      { min: 88000000, max: 150000000, rate: 0.35 },
      { min: 150000000, max: 300000000, rate: 0.38 },
      { min: 300000000, max: 500000000, rate: 0.40 },
      { min: 500000000, max: 1000000000, rate: 0.42 },
      { min: 1000000000, max: null, rate: 0.45 },
    ],
    minimumWage: {
      hourly2025: 10030,
      hourly2026: 10570,
      daily2025: 80240,
      daily2026: 84560,
    },
    overtime: {
      multiplier: 1.5,
      holidayMultiplier: 2.0,
      description: "연장근무 150%, 휴일근무 200%",
    },
  };
}

