import 'dart:typed_data';

/// Writes [pdf] to `Documents/<folder>/<file>` and returns its path.
Future<String> saveReceiptPdf(
  Uint8List pdf, {
  required String folder,
  required String file,
}) => throw UnsupportedError('Receipts are saved on the desk app only.');

/// Shows [path] in the file manager.
Future<void> showInFolder(String path) =>
    throw UnsupportedError('Receipts are saved on the desk app only.');
