import 'package:flutter/material.dart';

class SriLankaBank {
  const SriLankaBank({required this.name, required this.sender, required this.color});

  final String name;
  final String sender;
  final Color color;

  String get initials {
    final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2);
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}

const sriLankaBanks = <SriLankaBank>[
  SriLankaBank(name: 'Amana Bank PLC', sender: 'AMANA', color: Color(0xFF1F7A4D)),
  SriLankaBank(name: 'Bank of Ceylon', sender: 'BOC', color: Color(0xFFF5C400)),
  SriLankaBank(name: 'Cargills Bank Limited', sender: 'Cargills Bank', color: Color(0xFFE85D04)),
  SriLankaBank(name: 'Commercial Bank of Sri Lanka', sender: 'COMBANK', color: Color(0xFF1B4F9C)),
  SriLankaBank(name: 'DFCC Bank', sender: 'DFCC', color: Color(0xFFE10600)),
  SriLankaBank(name: 'Dialog Finance', sender: 'DIALOG', color: Color(0xFFED1C24)),
  SriLankaBank(name: 'Frimi', sender: 'FRIMI', color: Color(0xFFFF6A00)),
  SriLankaBank(name: 'Hatton National Bank', sender: 'HNB', color: Color(0xFF0057B8)),
  SriLankaBank(name: 'Hongkong and Shanghai Banking Corporation', sender: 'HSBC', color: Color(0xFFDB0011)),
  SriLankaBank(name: 'National Development Bank', sender: 'NDB', color: Color(0xFF111111)),
  SriLankaBank(name: 'National Savings Bank', sender: 'NSB', color: Color(0xFF0033A0)),
  SriLankaBank(name: 'Nations Trust Bank', sender: 'NTB', color: Color(0xFF00A3E0)),
  SriLankaBank(name: 'PEOPLES Bank', sender: 'Peoples Bank', color: Color(0xFFC5A572)),
  SriLankaBank(name: 'Sampath Bank', sender: 'SAMPATH', color: Color(0xFFE87722)),
  SriLankaBank(name: 'Seylan Bank', sender: 'SEYLAN', color: Color(0xFFE10600)),
  SriLankaBank(name: 'Standard Chartered', sender: 'Standard Chartered', color: Color(0xFF0072AA)),
  SriLankaBank(name: 'Union Bank', sender: 'UNIONBANK', color: Color(0xFF0033A0)),
];
