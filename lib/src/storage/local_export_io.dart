import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> writeExportFile(String filename, List<int> bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final folder = await Directory('${dir.path}/spike_prime_studio/exports').create(recursive: true);
  final file = File('${folder.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
