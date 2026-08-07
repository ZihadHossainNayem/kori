/// A currency the picker offers.
class CurrencyOption {
  const CurrencyOption(this.code, this.name);

  final String code;
  final String name;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return code.toLowerCase().contains(q) || name.toLowerCase().contains(q);
  }
}

/// Curated rather than exhaustive: enough to cover most users without a
/// 180-entry scroll. South and Southeast Asian and Gulf currencies are listed
/// deliberately — remittance corridors are exactly where multi-currency
/// tracking matters and where paid apps are least affordable.
const List<CurrencyOption> currencies = [
  CurrencyOption('BDT', 'Bangladeshi Taka'),
  CurrencyOption('INR', 'Indian Rupee'),
  CurrencyOption('PKR', 'Pakistani Rupee'),
  CurrencyOption('LKR', 'Sri Lankan Rupee'),
  CurrencyOption('NPR', 'Nepalese Rupee'),
  CurrencyOption('USD', 'US Dollar'),
  CurrencyOption('EUR', 'Euro'),
  CurrencyOption('GBP', 'Pound Sterling'),
  CurrencyOption('AED', 'UAE Dirham'),
  CurrencyOption('SAR', 'Saudi Riyal'),
  CurrencyOption('QAR', 'Qatari Riyal'),
  CurrencyOption('KWD', 'Kuwaiti Dinar'),
  CurrencyOption('BHD', 'Bahraini Dinar'),
  CurrencyOption('OMR', 'Omani Rial'),
  CurrencyOption('MYR', 'Malaysian Ringgit'),
  CurrencyOption('SGD', 'Singapore Dollar'),
  CurrencyOption('THB', 'Thai Baht'),
  CurrencyOption('IDR', 'Indonesian Rupiah'),
  CurrencyOption('PHP', 'Philippine Peso'),
  CurrencyOption('VND', 'Vietnamese Dong'),
  CurrencyOption('CNY', 'Chinese Yuan'),
  CurrencyOption('JPY', 'Japanese Yen'),
  CurrencyOption('KRW', 'South Korean Won'),
  CurrencyOption('HKD', 'Hong Kong Dollar'),
  CurrencyOption('AUD', 'Australian Dollar'),
  CurrencyOption('NZD', 'New Zealand Dollar'),
  CurrencyOption('CAD', 'Canadian Dollar'),
  CurrencyOption('CHF', 'Swiss Franc'),
  CurrencyOption('SEK', 'Swedish Krona'),
  CurrencyOption('NOK', 'Norwegian Krone'),
  CurrencyOption('DKK', 'Danish Krone'),
  CurrencyOption('PLN', 'Polish Zloty'),
  CurrencyOption('CZK', 'Czech Koruna'),
  CurrencyOption('TRY', 'Turkish Lira'),
  CurrencyOption('RUB', 'Russian Ruble'),
  CurrencyOption('EGP', 'Egyptian Pound'),
  CurrencyOption('NGN', 'Nigerian Naira'),
  CurrencyOption('KES', 'Kenyan Shilling'),
  CurrencyOption('GHS', 'Ghanaian Cedi'),
  CurrencyOption('ZAR', 'South African Rand'),
  CurrencyOption('MAD', 'Moroccan Dirham'),
  CurrencyOption('BRL', 'Brazilian Real'),
  CurrencyOption('MXN', 'Mexican Peso'),
  CurrencyOption('ARS', 'Argentine Peso'),
  CurrencyOption('CLP', 'Chilean Peso'),
  CurrencyOption('COP', 'Colombian Peso'),
];

/// The display name for [code], or the code itself if it is not in the list.
String currencyName(String code) {
  final upper = code.toUpperCase();
  for (final option in currencies) {
    if (option.code == upper) return option.name;
  }
  return upper;
}
