/// The scanner implementation used to capture documents.
enum ScannerType {
  /// Uses the platform's document scanner (ML Kit on Android, VisionKit on
  /// iOS) and falls back to [edgeDetection] if it is not available, e.g. on
  /// Android devices without Google Play Services.
  automatic,

  /// Always uses the built-in, OpenCV based scanner.
  edgeDetection,
}
