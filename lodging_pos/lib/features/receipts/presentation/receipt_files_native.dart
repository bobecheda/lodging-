import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Writes [pdf] to `Documents/<folder>/<file>` (creating the folder) and
/// returns its path.
Future<String> saveReceiptPdf(
  Uint8List pdf, {
  required String folder,
  required String file,
}) async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory('${documents.path}${Platform.pathSeparator}$folder');
  await dir.create(recursive: true);
  final path = '${dir.path}${Platform.pathSeparator}$file';
  await File(path).writeAsBytes(pdf, flush: true);
  return path;
}

/// Opens Explorer with [path] selected (Windows); elsewhere, its folder.
Future<void> showInFolder(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else {
    await Process.run('xdg-open', [File(path).parent.path]);
  }
}
