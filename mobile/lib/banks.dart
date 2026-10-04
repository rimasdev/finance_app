import 'package:flutter/material.dart';

import 'theme.dart';

class SriLankaBank {
  const SriLankaBank({
    required this.name,
    required this.sender,
    required this.color,
    this.logo,
  });

  final String name;
  final String sender;
  final Color color;
  final String? logo;

  String get initials {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}

const sriLankaBanks = <SriLankaBank>[
  SriLankaBank(
    name: 'Amana Bank PLC',
    sender: 'AMANA',
    color: Color(0xFF1F7A4D),
    logo: 'images/banks/Amana.jpeg',
  ),
  SriLankaBank(
    name: 'Bank of Ceylon',
    sender: 'BOC',
    color: Color(0xFFF5C400),
    logo: 'images/banks/BOC.jpg',
  ),
  SriLankaBank(
    name: 'Cargills Bank Limited',
    sender: 'Cargills Bank',
    color: Color(0xFFE85D04),
    logo: 'images/banks/Cargills .png',
  ),
  SriLankaBank(
    name: 'Commercial Bank of Sri Lanka',
    sender: 'COMBANK',
    color: Color(0xFF1B4F9C),
    logo: 'images/banks/Commerical Bank.png',
  ),
  SriLankaBank(
    name: 'DFCC Bank',
    sender: 'DFCC',
    color: Color(0xFFE10600),
    logo: 'images/banks/DFCC.jpg',
  ),
  SriLankaBank(
    name: 'Dialog Finance',
    sender: 'DIALOG',
    color: Color(0xFFED1C24),
  ),
  SriLankaBank(name: 'Frimi', sender: 'FRIMI', color: Color(0xFFFF6A00)),
  SriLankaBank(
    name: 'Hatton National Bank',
    sender: 'HNB',
    color: Color(0xFF0057B8),
    logo: 'images/banks/HNB.png',
  ),
  SriLankaBank(
    name: 'Hongkong and Shanghai Banking Corporation',
    sender: 'HSBC',
    color: Color(0xFFDB0011),
  ),
  SriLankaBank(
    name: 'National Development Bank',
    sender: 'NDB',
    color: Color(0xFF111111),
    logo: 'images/banks/NDB.png',
  ),
  SriLankaBank(
    name: 'National Savings Bank',
    sender: 'NSB',
    color: Color(0xFF0033A0),
    logo: 'images/banks/NSB.png',
  ),
  SriLankaBank(
    name: 'Nations Trust Bank',
    sender: 'NTB',
    color: Color(0xFF00A3E0),
  ),
  SriLankaBank(
    name: 'Pan Asia Bank',
    sender: 'PABC',
    color: Color(0xFFE31C23),
    logo: 'images/banks/Pan Asia.png',
  ),
  SriLankaBank(
    name: 'PEOPLES Bank',
    sender: 'Peoples Bank',
    color: Color(0xFFC5A572),
  ),
  SriLankaBank(
    name: 'Sampath Bank',
    sender: 'SAMPATH',
    color: Color(0xFFE87722),
    logo: 'images/banks/Sampath Bank.png',
  ),
  SriLankaBank(name: 'Seylan Bank', sender: 'SEYLAN', color: Color(0xFFE10600)),
  SriLankaBank(
    name: 'Standard Chartered',
    sender: 'Standard Chartered',
    color: Color(0xFF0072AA),
  ),
  SriLankaBank(
    name: 'Union Bank',
    sender: 'UNIONBANK',
    color: Color(0xFF0033A0),
    logo: 'images/banks/Union bank.jpeg',
  ),
];

SriLankaBank? bankByName(String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final bank in sriLankaBanks) {
    if (bank.name.toLowerCase() == key) return bank;
  }
  return null;
}

Future<SriLankaBank?> showBankPicker(BuildContext context) {
  return showModalBottomSheet<SriLankaBank>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FolioColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => const BankPickerSheet(),
  );
}

class BankPickerSheet extends StatefulWidget {
  const BankPickerSheet({super.key});

  @override
  State<BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<BankPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final banks = sriLankaBanks.where((bank) {
      if (query.isEmpty) return true;
      return bank.name.toLowerCase().contains(query) ||
          bank.sender.toLowerCase().contains(query);
    }).toList();
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: FolioColors.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select Bank',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search bank...',
                  prefixIcon: Icon(Icons.search, color: FolioColors.muted),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: banks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final bank = banks[index];
                  return Material(
                    color: FolioColors.card,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: BankMark(bank: bank, size: 44),
                      title: Text(
                        bank.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        bank.sender,
                        style: const TextStyle(
                          color: FolioColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, bank),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BankMark extends StatelessWidget {
  const BankMark({super.key, required this.bank, this.size = 48});

  final SriLankaBank bank;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: bank.logo == null
          ? Center(
              child: Text(
                bank.initials,
                style: TextStyle(
                  color: bank.color,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.28,
                ),
              ),
            )
          : Image.asset(bank.logo!, fit: BoxFit.contain),
    );
  }
}
