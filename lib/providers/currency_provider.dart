import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/currency_service.dart';

/// Fetches and exposes the company's configured currency for formatting amounts.
class CurrencyProvider extends ChangeNotifier {
  String _currency = 'USD';
  late NumberFormat _currencyFormat;
  bool _isLoading = false;
  String? _error;
  List<dynamic>? _lastCurrencyIdList;

  final CurrencyService _currencyService;

  final Map<String, String> currencyToLocale = {
    'USD': 'en_US',
    'EUR': 'de_DE',
    'GBP': 'en_GB',
    'INR': 'en_IN',
    'JPY': 'ja_JP',
    'CNY': 'zh_CN',
    'AUD': 'en_AU',
    'CAD': 'en_CA',
    'CHF': 'de_CH',
    'SGD': 'en_SG',
    'AED': 'ar_AE',
    'SAR': 'ar_SA',
    'QAR': 'ar_QA',
    'KWD': 'ar_KW',
    'BHD': 'ar_BH',
    'OMR': 'ar_OM',
    'MYR': 'ms_MY',
    'THB': 'th_TH',
    'IDR': 'id_ID',
    'PHP': 'fil_PH',
    'VND': 'vi_VN',
    'KRW': 'ko_KR',
    'TWD': 'zh_TW',
    'HKD': 'zh_HK',
    'NZD': 'en_NZ',
    'ZAR': 'en_ZA',
    'BRL': 'pt_BR',
    'MXN': 'es_MX',
    'ARS': 'es_AR',
    'CLP': 'es_CL',
    'COP': 'es_CO',
    'PEN': 'es_PE',
    'UYU': 'es_UY',
    'TRY': 'tr_TR',
    'ILS': 'he_IL',
    'EGP': 'ar_EG',
    'PKR': 'ur_PK',
    'BDT': 'bn_BD',
    'LKR': 'si_LK',
    'NPR': 'ne_NP',
    'MMK': 'my_MM',
    'KHR': 'km_KH',
    'LAK': 'lo_LA',
  };

  CurrencyProvider({CurrencyService? currencyService})
    : _currencyService = currencyService ?? CurrencyService.instance {
    final locale = currencyToLocale['USD'] ?? 'en_US';
    _currencyFormat = NumberFormat.currency(locale: locale, decimalDigits: 2);
    fetchCompanyCurrency();
  }

  String get currency => _currency;

  NumberFormat get currencyFormat => _currencyFormat;

  bool get isLoading => _isLoading;

  String? get error => _error;

  String get companyCurrencyId => _currency;

  List<dynamic>? get companyCurrencyIdList => _lastCurrencyIdList;

  /// Loads the company currency from Odoo and updates the formatter.
  Future<void> fetchCompanyCurrency() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final currencyData = await _currencyService.fetchCompanyCurrency();

      if (currencyData != null) {
        _currency = currencyData['name'];
        _lastCurrencyIdList = [currencyData['id'], currencyData['name']];

        final locale = currencyToLocale[_currency] ?? 'en_US';
        _currencyFormat = NumberFormat.currency(
          locale: locale,
          decimalDigits: 2,
        );
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns the currency symbol for the given ISO [currencyCode].
  String getCurrencySymbol(String currencyCode) {
    final Map<String, String> currencySymbols = {
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'INR': '₹',
      'JPY': '¥',
      'CNY': '¥',
      'AUD': 'A\$',
      'CAD': 'C\$',
      'CHF': 'CHF',
      'SGD': 'S\$',
      'AED': 'AED',
      'SAR': 'SR',
      'QAR': 'QR',
      'KWD': 'KD',
      'BHD': 'BD',
      'OMR': 'OMR',
      'MYR': 'RM',
      'THB': '฿',
      'IDR': 'Rp',
      'PHP': '₱',
      'VND': '₫',
      'KRW': '₩',
      'TWD': 'NT\$',
      'HKD': 'HK\$',
      'NZD': 'NZ\$',
      'ZAR': 'R',
      'BRL': 'R\$',
      'MXN': 'MX\$',
      'ARS': '\$',
      'CLP': '\$',
      'COP': '\$',
      'PEN': 'S/',
      'UYU': '\$U',
      'TRY': '₺',
      'ILS': '₪',
      'EGP': 'E£',
      'PKR': '₨',
      'BDT': '৳',
      'LKR': 'Rs',
      'NPR': 'रु',
      'MMK': 'K',
      'KHR': '៛',
      'LAK': '₭',
    };

    return currencySymbols[currencyCode] ?? currencyCode;
  }

  /// Formats [amount] with the appropriate currency symbol.
  String formatAmount(double amount, {String? currency}) {
    final currencyCode = currency ?? _currency;
    final symbol = getCurrencySymbol(currencyCode);
    final locale = currencyToLocale[currencyCode] ?? 'en_US';
    final formattedAmount = NumberFormat.currency(
      locale: locale,
      symbol: '',
      decimalDigits: 2,
    ).format(amount);

    return '$symbol $formattedAmount';
  }

  /// Resets currency state to USD defaults.
  Future<void> clearData() async {
    _currency = 'USD';
    final locale = currencyToLocale['USD'] ?? 'en_US';
    _currencyFormat = NumberFormat.currency(locale: locale, decimalDigits: 2);
    _isLoading = false;
    _error = null;
    _lastCurrencyIdList = null;
    notifyListeners();
  }

  void debugCurrencyFormatting() {
    final testCurrencies = ['USD', 'INR', 'EUR', 'GBP'];
    for (final currency in testCurrencies) {
      final locale = currencyToLocale[currency] ?? 'en_US';
      try {
        final formatter = NumberFormat.currency(
          locale: locale,
          decimalDigits: 2,
        );
      } catch (e) {}
    }
  }
}
