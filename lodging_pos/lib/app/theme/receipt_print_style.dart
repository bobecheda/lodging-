import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The printed receipt's page (FD-6): an 80 mm roll for a thermal printer;
/// an office printer centres it on its paper. The owner's printer is still
/// unknown, so this is the one place to change it.
const receiptPageFormat = PdfPageFormat.roll80;

/// The receipt's fonts, embedded in the PDF from the bundled assets so it
/// prints the same offline.
final class ReceiptFonts {
  const ReceiptFonts({
    required this.body,
    required this.bodyStrong,
    required this.heading,
    required this.mono,
    required this.monoStrong,
  });

  final pw.Font body;
  final pw.Font bodyStrong;
  final pw.Font heading;
  final pw.Font mono;
  final pw.Font monoStrong;

  static Future<ReceiptFonts> load(AssetBundle bundle) async {
    Future<pw.Font> font(String path) async =>
        pw.Font.ttf(await bundle.load(path));
    return ReceiptFonts(
      body: await font('assets/fonts/manrope/manrope-medium.ttf'),
      bodyStrong: await font('assets/fonts/manrope/manrope-bold.ttf'),
      heading: await font('assets/fonts/manrope/manrope-extrabold.ttf'),
      mono: await font('assets/fonts/ibm_plex_mono/IBMPlexMono-Medium.ttf'),
      monoStrong: await font(
        'assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf',
      ),
    );
  }
}

/// Black and white only, so a thermal printer loses nothing; sizes in
/// points for an 80 mm roll.
final class ReceiptPrintStyle {
  ReceiptPrintStyle(this.fonts);

  final ReceiptFonts fonts;

  static const ink = PdfColors.black;
  static const margin = 10.0;
  static const rule = 1.2;
  static const hairline = 0.5;
  static const gap = 6.0;

  pw.TextStyle get lodgingName =>
      pw.TextStyle(font: fonts.heading, fontSize: 14, color: ink);
  pw.TextStyle get caps => pw.TextStyle(
    font: fonts.bodyStrong,
    fontSize: 7.5,
    letterSpacing: 0.8,
    color: ink,
  );
  pw.TextStyle get receiptNumber =>
      pw.TextStyle(font: fonts.monoStrong, fontSize: 15, color: ink);
  pw.TextStyle get label =>
      pw.TextStyle(font: fonts.body, fontSize: 8.5, color: ink);
  pw.TextStyle get value =>
      pw.TextStyle(font: fonts.bodyStrong, fontSize: 8.5, color: ink);
  pw.TextStyle get monoValue =>
      pw.TextStyle(font: fonts.monoStrong, fontSize: 8.5, color: ink);
  pw.TextStyle get totalLabel =>
      pw.TextStyle(font: fonts.heading, fontSize: 10, color: ink);
  pw.TextStyle get total =>
      pw.TextStyle(font: fonts.monoStrong, fontSize: 15, color: ink);
  pw.TextStyle get copy =>
      pw.TextStyle(font: fonts.heading, fontSize: 11, color: ink);
  pw.TextStyle get footerStrong =>
      pw.TextStyle(font: fonts.heading, fontSize: 8.5, color: ink);
  pw.TextStyle get footer =>
      pw.TextStyle(font: fonts.body, fontSize: 7.5, color: ink);
}
