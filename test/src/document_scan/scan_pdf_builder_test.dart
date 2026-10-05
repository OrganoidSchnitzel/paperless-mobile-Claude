import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:paperless_mobile/features/document_scan/service/scan_pdf_builder.dart';
import 'package:pdf/pdf.dart';

void main() {
  group('pageFormatForImage', () {
    test('fits a portrait scan onto an A4 page', () {
      // 12 MP portrait image with A4 aspect ratio.
      final format = pageFormatForImage(3000, 4243);
      expect(format.width, closeTo(PdfPageFormat.a4.width, 1));
      expect(format.height, closeTo(PdfPageFormat.a4.height, 1));
      expect(format.marginLeft, 0);
    });

    test('keeps the aspect ratio of narrow receipts', () {
      final format = pageFormatForImage(1000, 4000);
      expect(format.height, closeTo(PdfPageFormat.a4.height, 1));
      expect(format.width / format.height, closeTo(1000 / 4000, 0.001));
    });

    test('uses a landscape page for landscape images', () {
      final format = pageFormatForImage(4243, 3000);
      expect(format.width, closeTo(PdfPageFormat.a4.height, 1));
      expect(format.height, closeTo(PdfPageFormat.a4.width, 1));
    });

    test('does not declare a resolution below 150 dpi', () {
      final format = pageFormatForImage(300, 150);
      // 300px at 150dpi = 2 inches.
      expect(format.width, closeTo(2 * PdfPageFormat.inch, 0.001));
      expect(format.height, closeTo(1 * PdfPageFormat.inch, 0.001));
    });
  });

  test('buildPdfFromImages creates one page per image', () async {
    final jpeg = img.encodeJpg(img.Image(width: 60, height: 80));
    final png = img.encodePng(img.Image(width: 80, height: 60));
    final pdf = await buildPdfFromImages([jpeg, png]);
    final content = String.fromCharCodes(pdf);
    expect(content.startsWith('%PDF'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(content).length, 2);
  });
}
