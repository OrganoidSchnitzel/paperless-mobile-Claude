import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:edge_detection/edge_detection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:paperless_mobile/core/service/file_service.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/settings/model/scanner_type.dart';

/// Captures documents using either the platform document scanner (ML Kit on
/// Android, VisionKit on iOS) or the OpenCV based edge_detection scanner.
///
/// Scanned pages are always stored as JPEG files in the temporary scans
/// directory, so that they survive app restarts.
class DocumentScannerService {
  static const _platformChannel = MethodChannel(
    'de.astubenbord.paperless_mobile/platform',
  );

  /// Maximum number of pages which can be captured in one scanner session.
  static const _maxPagesPerSession = 100;

  static bool? _isNativeScannerAvailable;

  const DocumentScannerService._();

  /// Whether the platform document scanner can be used on this device.
  static Future<bool> isNativeScannerAvailable() async {
    return _isNativeScannerAvailable ??= await _checkNativeScannerAvailable();
  }

  static Future<bool> _checkNativeScannerAvailable() async {
    if (Platform.isIOS) {
      return true;
    }
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _platformChannel.invokeMethod<bool>(
            'isGooglePlayServicesAvailable',
          ) ??
          false;
    } catch (error, stackTrace) {
      logger.fw(
        "Could not determine whether Google Play Services are available.",
        className: 'DocumentScannerService',
        methodName: '_checkNativeScannerAvailable',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Opens the scanner selected by [type] and returns the scanned pages in
  /// the order they were captured, or an empty list if the scan was cancelled.
  static Future<List<File>> scan({required ScannerType type}) async {
    final useNativeScanner =
        type == ScannerType.automatic && await isNativeScannerAvailable();
    if (useNativeScanner) {
      try {
        return await _scanWithNativeScanner();
      } on CunningDocumentScannerException catch (error, stackTrace) {
        if (error.code == 'permission_denied') {
          rethrow;
        }
        logger.fe(
          "Native document scanner failed, falling back to edge detection.",
          className: 'DocumentScannerService',
          methodName: 'scan',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return _scanWithEdgeDetection();
  }

  static Future<List<File>> _scanWithNativeScanner() async {
    final paths = await CunningDocumentScanner.getPictures(
      noOfPages: _maxPagesPerSession,
      // On Android, this adds an import button to the ML Kit scanner UI.
      // On iOS, this would show an additional selection menu before every
      // scan, so we stick to the camera there.
      scannerSource: Platform.isAndroid
          ? ScannerSource.cameraAndGallery
          : ScannerSource.camera,
      androidScannerMode: AndroidScannerMode.full,
      iosScannerOptions: IosScannerOptions(
        imageFormat: IosImageFormat.jpg,
        jpgCompressionQuality: 0.9,
      ),
    );
    if (paths == null || paths.isEmpty) {
      return [];
    }
    try {
      final scans = <File>[];
      for (final path in paths) {
        scans.add(await _storeAsJpeg(File(path)));
      }
      return scans;
    } finally {
      // The plugin keeps its own copies, which are not needed anymore.
      CunningDocumentScanner.cleanCache().catchError((_) {});
    }
  }

  static Future<List<File>> _scanWithEdgeDetection() async {
    final file = await FileService.instance.allocateTemporaryFile(
      PaperlessDirectoryType.scans,
      extension: 'jpeg',
      create: true,
    );
    bool success = false;
    try {
      success = await EdgeDetection.detectEdge(
        file.path,
        canUseGallery: true,
      );
    } finally {
      if (!success && await file.exists()) {
        await file.delete();
      }
    }
    if (!success || await file.length() == 0) {
      return [];
    }
    return [file];
  }

  /// Copies [source] into the scans directory, re-encoding it as JPEG if
  /// necessary (e.g. if the scanner returned a PNG).
  static Future<File> _storeAsJpeg(File source) async {
    final target = await FileService.instance.allocateTemporaryFile(
      PaperlessDirectoryType.scans,
      extension: 'jpeg',
    );
    final bytes = await source.readAsBytes();
    if (_isJpeg(bytes)) {
      return target.writeAsBytes(bytes, flush: true);
    }
    final jpegBytes = await compute(_encodeAsJpeg, bytes);
    return target.writeAsBytes(jpegBytes, flush: true);
  }

  static bool _isJpeg(Uint8List bytes) {
    return bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
  }
}

Uint8List _encodeAsJpeg(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException("Scanned image could not be decoded.");
  }
  return img.encodeJpg(image, quality: 90);
}
