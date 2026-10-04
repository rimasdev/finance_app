import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> persistAccountImage(String id, String sourcePath) async {
  final dir = await getApplicationDocumentsDirectory();
  final dest = File('${dir.path}/account_$id.jpg');
  await File(sourcePath).copy(dest.path);
  return dest.path;
}

bool accountImageReady(String path) {
  if (path.isEmpty) return false;
  return File(path).existsSync();
}

Widget accountImage(String path, double size) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
    ),
  );
}
