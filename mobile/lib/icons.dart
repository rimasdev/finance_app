import 'package:flutter/material.dart';

IconData iconFor(String key) {
  switch (key) {
    case 'transport':
      return Icons.directions_car_filled_rounded;
    case 'utilities':
      return Icons.bolt_rounded;
    case 'health':
      return Icons.health_and_safety_rounded;
    case 'debt':
      return Icons.account_balance_wallet_rounded;
    case 'dining':
      return Icons.restaurant_rounded;
    case 'entertainment':
      return Icons.confirmation_number_rounded;
    case 'personal':
      return Icons.spa_rounded;
    case 'shopping':
      return Icons.shopping_bag_rounded;
    case 'gifts':
      return Icons.card_giftcard_rounded;
    case 'education':
      return Icons.school_rounded;
    case 'work':
      return Icons.work_rounded;
    case 'transfer':
      return Icons.swap_horiz_rounded;
    case 'salary':
      return Icons.payments_rounded;
    case 'business':
      return Icons.storefront_rounded;
    default:
      return Icons.help_rounded;
  }
}

IconData accountIcon(String type) {
  switch (type) {
    case 'cash':
      return Icons.payments_rounded;
    case 'credit_card':
      return Icons.credit_card_rounded;
    case 'debit_card':
      return Icons.payment_rounded;
    default:
      return Icons.account_balance_rounded;
  }
}

String accountTypeLabel(String type) {
  switch (type) {
    case 'cash':
      return 'Cash';
    case 'credit_card':
      return 'Credit card';
    case 'debit_card':
      return 'Debit card';
    default:
      return 'Bank';
  }
}

Color colorFromHex(String hex) {
  final cleaned = hex.replaceAll('#', '');
  if (cleaned.length != 6) return const Color(0xFF9CA3AF);
  return Color(int.parse('FF$cleaned', radix: 16));
}
