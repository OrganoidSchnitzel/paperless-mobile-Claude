import 'dart:io';

import 'package:paperless_mobile/features/logging/data/logger.dart';

class AutoUploadResult {
  /// Number of files which have been uploaded.
  final int uploaded;

  /// Number of files which could not be uploaded and are still queued.
  final int failed;

  /// Task ids of the uploaded documents, if returned by the server.
  final List<String> taskIds;

  const AutoUploadResult({
    this.uploaded = 0,
    this.failed = 0,
    this.taskIds = const [],
  });
}

/// Uploads the files which were queued for automatic upload while the device
/// was offline.
class PendingFilesAutoUploader {
  /// Returns the files queued for upload, in the order they should be uploaded.
  final Future<List<File>> Function() getQueuedFiles;

  /// Uploads a file and returns the task id (if any). Throws on failure.
  final Future<String?> Function(File file) upload;

  /// Called after a file has been uploaded successfully, should remove the
  /// file from the queue.
  final Future<void> Function(File file) onUploaded;

  bool _isRunning = false;

  PendingFilesAutoUploader({
    required this.getQueuedFiles,
    required this.upload,
    required this.onUploaded,
  });

  /// Uploads all queued files. Files which cannot be uploaded remain queued.
  /// Calls while an upload is already running are ignored.
  Future<AutoUploadResult> uploadQueuedFiles() async {
    if (_isRunning) {
      return const AutoUploadResult();
    }
    _isRunning = true;
    try {
      final files = await getQueuedFiles();
      int uploaded = 0;
      int failed = 0;
      final taskIds = <String>[];
      for (final file in files) {
        final String? taskId;
        try {
          taskId = await upload(file);
        } catch (error, stackTrace) {
          failed++;
          logger.fe(
            "Could not upload pending file ${file.path}.",
            className: runtimeType.toString(),
            methodName: "uploadQueuedFiles",
            error: error,
            stackTrace: stackTrace,
          );
          continue;
        }
        uploaded++;
        if (taskId != null) {
          taskIds.add(taskId);
        }
        try {
          await onUploaded(file);
        } catch (error, stackTrace) {
          logger.fe(
            "Could not remove uploaded file ${file.path} from the queue.",
            className: runtimeType.toString(),
            methodName: "uploadQueuedFiles",
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      return AutoUploadResult(
        uploaded: uploaded,
        failed: failed,
        taskIds: taskIds,
      );
    } finally {
      _isRunning = false;
    }
  }
}
