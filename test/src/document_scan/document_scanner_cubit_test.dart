import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:paperless_mobile/core/bloc/loading_status.dart';
import 'package:paperless_mobile/features/document_scan/cubit/document_scanner_cubit.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/notifications/services/local_notification_service.dart';

void main() {
  setUpAll(() {
    logger = Logger(level: Level.off);
  });

  test(
    'initialize emits an error state if scans cannot be restored',
    () async {
      // The FileService has not been initialized, so accessing the scans
      // directory fails.
      final cubit = DocumentScannerCubit(LocalNotificationService());
      await cubit.initialize();
      expect(cubit.state.status, LoadingStatus.error);
      expect(cubit.state.scans, isEmpty);
    },
  );
}
