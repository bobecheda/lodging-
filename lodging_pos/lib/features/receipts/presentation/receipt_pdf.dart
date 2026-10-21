import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../app/theme/receipt_print_style.dart';
import '../domain/receipt.dart';

/// The receipt as a one-page PDF on [receiptPageFormat], following the
/// artboard "Receipt — on screen and PDF": lodging name, RECEIPT and its
/// number (COPY on reprints), the stay, the charge lines and total, how it
/// was paid, and the footer. Black and white only.
Future<Uint8List> buildReceiptPdf(Receipt r, ReceiptFonts fonts) {
  final s = ReceiptPrintStyle(fonts);

  pw.Widget row(String label, String value, {bool mono = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: s.label),
        pw.SizedBox(width: ReceiptPrintStyle.gap),
        pw.Expanded(
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: mono ? s.monoValue : s.value,
          ),
        ),
      ],
    ),
  );

  pw.Widget dashed() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: ReceiptPrintStyle.gap),
    child: pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: ReceiptPrintStyle.ink,
            width: ReceiptPrintStyle.hairline,
            style: pw.BorderStyle.dashed,
          ),
        ),
      ),
    ),
  );

  pw.Widget solid() => pw.Container(
    height: ReceiptPrintStyle.rule,
    color: ReceiptPrintStyle.ink,
  );

  final doc = pw.Document(
    title: '${r.receiptNumber}${r.isCopy ? ' COPY' : ''}',
    author: r.lodgingName,
  );
  doc.addPage(
    pw.Page(
      pageFormat: receiptPageFormat.copyWith(
        marginLeft: ReceiptPrintStyle.margin,
        marginRight: ReceiptPrintStyle.margin,
        marginTop: ReceiptPrintStyle.margin,
        marginBottom: ReceiptPrintStyle.margin,
      ),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            r.lodgingName,
            textAlign: pw.TextAlign.center,
            style: s.lodgingName,
          ),
          pw.Text(
            'LODGING',
            textAlign: pw.TextAlign.center,
            style: s.lodgingWord,
          ),
          pw.SizedBox(height: ReceiptPrintStyle.gap),
          solid(),
          pw.SizedBox(height: ReceiptPrintStyle.gap),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('RECEIPT', style: s.caps),
                    pw.Text(r.receiptNumber, style: s.receiptNumber),
                  ],
                ),
              ),
              pw.Text(r.issued, textAlign: pw.TextAlign.right, style: s.label),
            ],
          ),
          if (r.isCopy) ...[
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: ReceiptPrintStyle.ink,
                  width: ReceiptPrintStyle.rule,
                ),
              ),
              child: pw.Text(
                'COPY',
                textAlign: pw.TextAlign.center,
                style: s.copy,
              ),
            ),
          ],
          pw.SizedBox(height: ReceiptPrintStyle.gap),
          row('Guest', r.guestName),
          row('Room / bed', r.roomAndBed),
          if (r.category case final category?) row('Category', category),
          for (final (label, value) in r.stayRows) row(label, value),
          dashed(),
          for (final (label, amount) in r.chargeRows)
            row(label, amount, mono: true),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(child: pw.Text('Total paid', style: s.totalLabel)),
              pw.Text(r.totalText, style: s.total),
            ],
          ),
          dashed(),
          row('Paid by', r.paidBy),
          if (r.mpesaCode case final code?)
            row('M-Pesa code', code, mono: true),
          row('Served by', r.servedBy),
          pw.SizedBox(height: ReceiptPrintStyle.gap * 2),
          solid(),
          pw.SizedBox(height: ReceiptPrintStyle.gap),
          pw.Text(
            r.footer.first,
            textAlign: pw.TextAlign.center,
            style: s.footerStrong,
          ),
          for (final line in r.footer.skip(1))
            pw.Text(line, textAlign: pw.TextAlign.center, style: s.footer),
        ],
      ),
    ),
  );
  return doc.save();
}
