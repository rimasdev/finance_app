import 'package:web/web.dart';

Future<String> saveCsv(String filename, String content) async {
  final anchor = HTMLAnchorElement()
    ..href = 'data:text/csv;charset=utf-8,${Uri.encodeComponent(content)}'
    ..download = filename;
  anchor.click();
  return 'Downloaded $filename';
}
