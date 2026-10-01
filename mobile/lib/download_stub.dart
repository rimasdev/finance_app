import 'package:flutter/services.dart';

Future<String> saveCsv(String filename, String content) async {
  await Clipboard.setData(ClipboardData(text: content));
  return 'CSV copied. Paste it into a spreadsheet.';
}
