import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/theme/receipt_print_style.dart';
import '../../../core/audit/audit_writer.dart';
import '../../../core/database/database_provider.dart';
import '../data/receipts_repository.dart';
import '../domain/receipt.dart';
import 'receipt_files.dart';

part 'receipts_providers.g.dart';

@Riverpod(keepAlive: true)
ReceiptsRepository receiptsRepository(Ref ref) => ReceiptsRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
);

/// One receipt, watched: it turns into a COPY as soon as it's printed.
@riverpod
Stream<Receipt> receipt(Ref ref, String paymentId) =>
    ref.watch(receiptsRepositoryProvider).watchReceipt(paymentId);

/// The Receipts list for what's typed in its search box.
@riverpod
Stream<List<ReceiptSummary>> receiptList(Ref ref, String text) =>
    ref.watch(receiptsRepositoryProvider).watchReceipts(text);

/// The bundled fonts, embedded in every receipt PDF.
@Riverpod(keepAlive: true)
Future<ReceiptFonts> receiptFonts(Ref ref) => ReceiptFonts.load(rootBundle);

/// Where a receipt PDF goes. Tests replace it: printing needs the real
/// Windows print dialog.
abstract interface class ReceiptOutput {
  /// Opens the print dialog. True once printed; false if cancelled.
  Future<bool> print(Uint8List pdf, {required String name});

  /// Saves [pdf] as `Documents/<folder>/<file>`; returns its path.
  Future<String> save(
    Uint8List pdf, {
    required String folder,
    required String file,
  });

  /// Shows the saved file in Explorer.
  Future<void> openFolder(String path);
}

final class DeviceReceiptOutput implements ReceiptOutput {
  const DeviceReceiptOutput();

  @override
  Future<bool> print(Uint8List pdf, {required String name}) =>
      Printing.layoutPdf(
        onLayout: (_) async => pdf,
        name: name,
        format: receiptPageFormat,
      );

  @override
  Future<String> save(
    Uint8List pdf, {
    required String folder,
    required String file,
  }) => saveReceiptPdf(pdf, folder: folder, file: file);

  @override
  Future<void> openFolder(String path) => showInFolder(path);
}

@Riverpod(keepAlive: true)
ReceiptOutput receiptOutput(Ref ref) => const DeviceReceiptOutput();
