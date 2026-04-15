/// Price / cost-of-living data for each country.
/// Main cities: KR=Seoul, JP=Tokyo, CA=Calgary, AU=Brisbane, US=Austin TX.
/// 3-room areas: KR=노원구, JP=Nerima, CA=Calgary AB, AU=Brisbane QLD, US=Austin TX.

import 'country_data.dart';

/// Approximate USD exchange rates (April 2026)
/// Used for cross-country comparison charts only.
const Map<CountryCode, double> usdRates = {
  CountryCode.kr: 1450,   // 1 USD = 1,450 KRW
  CountryCode.jp: 150,    // 1 USD = 150 JPY
  CountryCode.ca: 1.38,   // 1 USD = 1.38 CAD
  CountryCode.au: 1.55,   // 1 USD = 1.55 AUD
  CountryCode.us: 1.0,    // 1 USD = 1 USD
};

class HousingOption {
  final String typeEn;
  final String? typeLocal;
  final double threeRoomPrice;

  const HousingOption({
    required this.typeEn,
    this.typeLocal,
    required this.threeRoomPrice,
  });
}

class PriceData {
  final String cityEn;
  final String? cityLocal;
  final String threeRoomAreaEn;      // specific area for 3-room prices
  final String? threeRoomAreaLocal;
  final double bigMacPrice;          // local currency
  final double rentOneBedroomCenter; // monthly, local currency
  final double rentThreeRoom;        // monthly, 3-room rent in threeRoomArea
  final List<HousingOption> housing; // apartment, villa, house, etc.
  final double propertyTaxRate;      // annual % of property value
  final String propertyTaxNoteEn;
  final String? propertyTaxNoteLocal;
  final double utilities1Room;       // monthly: electric + gas + water (~30sqm)
  final double utilities3Room;       // monthly: electric + gas + water (~85sqm)
  final double monthlyInternet;

  const PriceData({
    required this.cityEn,
    this.cityLocal,
    required this.threeRoomAreaEn,
    this.threeRoomAreaLocal,
    required this.bigMacPrice,
    required this.rentOneBedroomCenter,
    required this.rentThreeRoom,
    required this.housing,
    required this.propertyTaxRate,
    this.propertyTaxNoteEn = '',
    this.propertyTaxNoteLocal,
    required this.utilities1Room,
    required this.utilities3Room,
    required this.monthlyInternet,
  });
}

final Map<CountryCode, PriceData> countryPrices = {
  CountryCode.kr: const PriceData(
    cityEn: 'Seoul',
    cityLocal: '서울',
    threeRoomAreaEn: 'Nowon-gu',
    threeRoomAreaLocal: '노원구',
    bigMacPrice: 5000,
    rentOneBedroomCenter: 850000,
    rentThreeRoom: 1200000,           // ₩1,200,000/month (노원구 3룸)
    housing: [
      HousingOption(
        typeEn: 'Apartment',
        typeLocal: '아파트',
        threeRoomPrice: 500000000,    // 5억 (노원구)
      ),
      HousingOption(
        typeEn: 'Villa',
        typeLocal: '빌라',
        threeRoomPrice: 250000000,    // 2.5억 (노원구)
      ),
    ],
    propertyTaxRate: 0.0025,
    propertyTaxNoteEn: '0.1~0.4% residential + comprehensive holding tax if over threshold',
    propertyTaxNoteLocal: '주택분 재산세 0.1~0.4% + 종합부동산세 (기준 초과 시)',
    utilities1Room: 80000,            // ₩80,000 (~30sqm)
    utilities3Room: 150000,           // ₩150,000 (~85sqm)
    monthlyInternet: 30000,
  ),
  CountryCode.jp: const PriceData(
    cityEn: 'Tokyo',
    cityLocal: '東京',
    threeRoomAreaEn: 'Nerima, Tokyo',
    threeRoomAreaLocal: '練馬区',
    bigMacPrice: 450,
    rentOneBedroomCenter: 113000,      // ¥113,000/month (Tokyo 1R)
    rentThreeRoom: 130000,            // ¥130,000/month (Nerima 3LDK)
    housing: [
      HousingOption(
        typeEn: 'Apartment',
        typeLocal: 'マンション',
        threeRoomPrice: 40000000,     // 4,000万 (Nerima 3LDK)
      ),
      HousingOption(
        typeEn: 'Detached House',
        typeLocal: '一戸建て',
        threeRoomPrice: 50000000,     // 5,000万 (Nerima 3LDK with yard)
      ),
    ],
    propertyTaxRate: 0.017,
    propertyTaxNoteEn: '1.4% fixed asset tax + 0.3% city planning tax',
    propertyTaxNoteLocal: '固定資産税 1.4% + 都市計画税 0.3%',
    utilities1Room: 8000,             // ¥8,000 (~30sqm)
    utilities3Room: 13000,            // ¥13,000 (~85sqm)
    monthlyInternet: 5000,
  ),
  CountryCode.ca: const PriceData(
    cityEn: 'Calgary',
    threeRoomAreaEn: 'Calgary, AB',
    bigMacPrice: 7.47,
    rentOneBedroomCenter: 1674,
    rentThreeRoom: 2200,              // C$2,200/month (Calgary 3BR)
    housing: [
      HousingOption(
        typeEn: 'Apartment',
        threeRoomPrice: 350000,       // C$350K (3BR apartment/condo)
      ),
      HousingOption(
        typeEn: 'Townhouse',
        threeRoomPrice: 550000,       // C$550K (3BR townhouse with yard)
      ),
    ],
    propertyTaxRate: 0.0065,
    propertyTaxNoteEn: 'Municipal + provincial education tax (~0.6-0.7%)',
    utilities1Room: 200,              // C$200 (~30sqm)
    utilities3Room: 350,              // C$350 (~85sqm)
    monthlyInternet: 80,
  ),
  CountryCode.au: const PriceData(
    cityEn: 'Brisbane',
    threeRoomAreaEn: 'Brisbane, QLD',
    bigMacPrice: 7.45,
    rentOneBedroomCenter: 2200,
    rentThreeRoom: 2800,              // A$2,800/month (Brisbane 3BR)
    housing: [
      HousingOption(
        typeEn: 'Apartment',
        threeRoomPrice: 500000,       // A$500K (3BR apartment/unit)
      ),
      HousingOption(
        typeEn: 'Townhouse',
        threeRoomPrice: 750000,       // A$750K (3BR townhouse with yard)
      ),
    ],
    propertyTaxRate: 0.004,          // ~0.4% (council rates)
    propertyTaxNoteEn: 'Council rates ~0.3-0.5% annually. Land tax exempt for primary residence.',
    utilities1Room: 150,              // A$150 (~30sqm)
    utilities3Room: 250,              // A$250 (~85sqm)
    monthlyInternet: 80,
  ),
  CountryCode.us: const PriceData(
    cityEn: 'Austin',
    threeRoomAreaEn: 'Austin, TX',
    bigMacPrice: 5.79,
    rentOneBedroomCenter: 1524,
    rentThreeRoom: 2100,              // $2,100/month (Austin 3BR)
    housing: [
      HousingOption(
        typeEn: 'Apartment',
        threeRoomPrice: 280000,       // $280K (3BR apartment/condo)
      ),
      HousingOption(
        typeEn: 'Townhouse',
        threeRoomPrice: 420000,       // $420K (3BR townhouse with yard)
      ),
    ],
    propertyTaxRate: 0.018,
    propertyTaxNoteEn: 'Texas has no state income tax but high property tax (~1.6-2.0%)',
    utilities1Room: 120,              // $120 (~30sqm)
    utilities3Room: 200,              // $200 (~85sqm)
    monthlyInternet: 60,
  ),
};
