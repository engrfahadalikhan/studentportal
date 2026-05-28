import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared resources used by every FYP form PDF — logos and the four
/// Times Roman font variants.
class FypPdfAssets {
  const FypPdfAssets({
    required this.logoImage,
    required this.csLogoImage,
    required this.regularFont,
    required this.boldFont,
    required this.italicFont,
    required this.boldItalicFont,
  });

  final pw.MemoryImage logoImage;
  final pw.MemoryImage csLogoImage;
  final pw.Font regularFont;
  final pw.Font boldFont;
  final pw.Font italicFont;
  final pw.Font boldItalicFont;

  static Future<FypPdfAssets> load() async {
    final logoBytes = await rootBundle.load('assets/image1.png');
    final csLogoBytes = await rootBundle.load('assets/cs_logo.jpeg');
    final regularFontBytes = await rootBundle.load('assets/fonts/times.ttf');
    final boldFontBytes = await rootBundle.load('assets/fonts/timesbd.ttf');
    final italicFontBytes = await rootBundle.load('assets/fonts/timesi.ttf');
    final boldItalicFontBytes =
        await rootBundle.load('assets/fonts/timesbi.ttf');

    return FypPdfAssets(
      logoImage: pw.MemoryImage(logoBytes.buffer.asUint8List()),
      csLogoImage: pw.MemoryImage(csLogoBytes.buffer.asUint8List()),
      regularFont: pw.Font.ttf(regularFontBytes),
      boldFont: pw.Font.ttf(boldFontBytes),
      italicFont: pw.Font.ttf(italicFontBytes),
      boldItalicFont: pw.Font.ttf(boldItalicFontBytes),
    );
  }
}

/// Standard AUST + Department + form-title header used on every FYP form.
pw.Widget fypHeader(
  FypPdfAssets assets, {
  required String formTitle,
  required String subTitle,
}) {
  return pw.Column(
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 58,
            child: pw.Image(
              assets.logoImage,
              height: 60,
              fit: pw.BoxFit.contain,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text(
                  'ABBOTTABAD UNIVERSITY OF SCIENCE & TECHNOLOGY',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: assets.boldItalicFont,
                    fontSize: 14.5,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Department of Computer Science',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: assets.boldFont, fontSize: 11),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  formTitle,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: assets.boldFont, fontSize: 13),
                ),
                if (subTitle.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    subTitle,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: assets.boldFont,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          pw.SizedBox(
            width: 58,
            child: pw.Image(
              assets.csLogoImage,
              height: 60,
              fit: pw.BoxFit.contain,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 5),
      pw.Container(height: 0.9, color: PdfColors.black),
    ],
  );
}

/// Builds a labelled 2-column "Key : Value" table, used by many forms.
pw.Widget fypInfoTable(
  List<List<String>> rows,
  pw.Font boldFont, {
  double labelWidth = 130,
}) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: {
      0: pw.FixedColumnWidth(labelWidth),
      1: const pw.FlexColumnWidth(),
    },
    children: rows
        .map(
          (row) => pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 5,
                ),
                child: pw.Text(
                  row[0],
                  style: pw.TextStyle(font: boldFont, fontSize: 10),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 5,
                ),
                child: pw.Text(
                  row[1].isEmpty ? '—' : row[1],
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        )
        .toList(),
  );
}

/// Section heading bar used to separate form sections.
pw.Widget fypSectionTitle(String text, pw.Font boldFont) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    color: const PdfColor.fromInt(0xFFE9E8F6),
    child: pw.Text(
      text,
      style: pw.TextStyle(font: boldFont, fontSize: 11),
    ),
  );
}

/// Footer signature blocks (FYP Coordinator + HoD / Chairman).
pw.Widget fypFooterSignatures(
  pw.Font boldFont, {
  String leftLabel = 'FYP Coordinator',
  String rightLabel = 'Chairman, Department of Computer Science, AUST',
}) {
  pw.Widget block(String label) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            height: 22,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(width: 0.7, color: PdfColors.black),
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: boldFont, fontSize: 10),
          ),
        ],
      ),
    );
  }

  return pw.Row(
    children: [
      block(leftLabel),
      pw.SizedBox(width: 40),
      block(rightLabel),
    ],
  );
}

/// QR widget with caption — used so faculty can scan and pull up the record.
pw.Widget fypQrPanel({
  required String qrData,
  required String caption,
  required String captionDetail,
  required pw.Font boldFont,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.6, color: PdfColors.black),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: 76,
          height: 76,
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrData,
            drawText: false,
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                caption,
                style: pw.TextStyle(font: boldFont, fontSize: 11),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                captionDetail,
                style: const pw.TextStyle(fontSize: 9, lineSpacing: 1),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                qrData,
                style: pw.TextStyle(font: boldFont, fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
