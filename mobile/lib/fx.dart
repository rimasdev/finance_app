import 'dart:convert';

import 'package:http/http.dart' as http;

import 'format.dart';

class ExchangeRates {
  const ExchangeRates({
    required this.date,
    required this.lkrPerUsd,
    required this.usdPerEur,
    required this.usdPerGbp,
  });

  final String date;
  final double lkrPerUsd;
  final double usdPerEur;
  final double usdPerGbp;

  double? lkrPer(String currency) {
    switch (currency.toUpperCase()) {
      case '':
      case 'LKR':
        return 1;
      case 'USD':
        return lkrPerUsd;
      case 'EUR':
        return usdPerEur == 0 ? null : lkrPerUsd / usdPerEur;
      case 'GBP':
        return usdPerGbp == 0 ? null : lkrPerUsd / usdPerGbp;
      default:
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'lkr': lkrPerUsd,
        'eur': usdPerEur,
        'gbp': usdPerGbp,
      };

  factory ExchangeRates.fromJson(Map<String, dynamic> json) => ExchangeRates(
        date: json['date'] as String? ?? '',
        lkrPerUsd: (json['lkr'] as num?)?.toDouble() ?? 0,
        usdPerEur: (json['eur'] as num?)?.toDouble() ?? 0,
        usdPerGbp: (json['gbp'] as num?)?.toDouble() ?? 0,
      );
}

String colomboDay([DateTime? now]) {
  final local = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

Future<ExchangeRates> fetchExchangeRates() async {
  final response = await http
      .get(Uri.parse(
        'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json',
      ))
      .timeout(const Duration(seconds: 12));
  if (response.statusCode >= 400) {
    throw Exception('Exchange rates are unavailable');
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final usd = body['usd'] as Map<String, dynamic>;
  return ExchangeRates(
    date: body['date'] as String? ?? '',
    lkrPerUsd: (usd['lkr'] as num).toDouble(),
    usdPerEur: (usd['eur'] as num).toDouble(),
    usdPerGbp: (usd['gbp'] as num).toDouble(),
  );
}

String foreignAmount(String currency, num value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2).split('.');
  final whole = fixed[0];
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  final text = '$buffer.${fixed[1]}';
  return negative ? '$currency -$text' : '$currency $text';
}

/// Home amounts are always rupees. A foreign amount uses today's rate.
String rupeesFor(double amount, String currency, ExchangeRates? rates) {
  final code = currency.toUpperCase();
  if (code.isEmpty || code == 'LKR') return money(amount);
  final rate = rates?.lkrPer(code);
  if (rate == null || rate == 0) return foreignAmount(code, amount);
  return money(amount * rate);
}
