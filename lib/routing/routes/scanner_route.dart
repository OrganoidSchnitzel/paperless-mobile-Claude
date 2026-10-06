import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:paperless_mobile/features/document_scan/view/scanner_page.dart';
import 'package:paperless_mobile/features/document_upload/view/document_upload_preparation_page.dart';
import 'package:paperless_mobile/routing/navigation_keys.dart';

import 'shells/authenticated_route.dart';

class ScannerBranch extends StatefulShellBranchData {
  static final GlobalKey<NavigatorState> $navigatorKey = scannerNavigatorKey;

  const ScannerBranch();
}

class ScannerRoute extends GoRouteData with $ScannerRoute {
  const ScannerRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const ScannerPage();
  }
}

class DocumentUploadRoute extends GoRouteData with $DocumentUploadRoute {
  static final GlobalKey<NavigatorState> $parentNavigatorKey =
      outerShellNavigatorKey;
  final FutureOr<Uint8List> $extra;
  final String? title;
  final String? filename;
  final String? fileExtension;
  final bool? instantUpload;
  final bool? trackProcessing;

  const DocumentUploadRoute({
    required this.$extra,
    this.title,
    this.filename,
    this.fileExtension,
    this.instantUpload,
    this.trackProcessing,
  });

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return DocumentUploadPreparationPage(
      title: title,
      fileExtension: fileExtension,
      filename: filename,
      fileBytes: $extra,
      instantUpload: instantUpload ?? false,
      trackProcessing: trackProcessing ?? false,
    );
  }
}
