import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Lowest resolution which is declared for an embedded scan. Small images
/// result in smaller pages instead of a lower resolution.
const _minDpi = 150.0;

/// Combines the given (JPEG or PNG) images into a single PDF document, one
/// image per page.
///
/// Pages keep the aspect ratio of their image and are scaled to fit on an A4
/// page (portrait or landscape, depending on the image). This keeps the
/// physical page size realistic, which matters for printing and for the OCR
/// on the server, which uses the resolution declared in the PDF.
///
/// The PDF is created in a background isolate.
Future<Uint8List> buildPdfFromImages(List<Uint8List> images) {
  assert(images.isNotEmpty);
  return compute(_buildPdf, images);
}

Future<Uint8List> _buildPdf(List<Uint8List> images) async {
  final doc = pw.Document();
  for (final bytes in images) {
    final image = pw.MemoryImage(bytes);
    final pageFormat = pageFormatForImage(
      image.width!.toDouble(),
      image.height!.toDouble(),
    );
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) =>
            pw.FullPage(ignoreMargins: true, child: pw.Image(image)),
      ),
    );
  }
  return doc.save();
}

/// Computes a page format for an image of the given size in pixels.
@visibleForTesting
PdfPageFormat pageFormatForImage(double widthPx, double heightPx) {
  final a4 = widthPx > heightPx ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
  final pointsPerPixel = min(
    min(a4.width / widthPx, a4.height / heightPx),
    PdfPageFormat.inch / _minDpi,
  );
  return PdfPageFormat(
    widthPx * pointsPerPixel,
    heightPx * pointsPerPixel,
    marginAll: 0,
  );
}
