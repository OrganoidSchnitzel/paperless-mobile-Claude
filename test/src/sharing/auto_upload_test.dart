import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/sharing/model/auto_upload_queue.dart';
import 'package:paperless_mobile/features/sharing/services/pending_files_auto_uploader.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    logger = Logger(level: Level.off);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('auto_upload_test');
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<File> createFile(String name) =>
      File('${tempDir.path}/$name').writeAsString(name);

  group('AutoUploadQueue', () {
    test('keeps files in order and ignores duplicates', () async {
      final queue = AutoUploadQueue(userId: 'user');
      final a = await createFile('a.pdf');
      final b = await createFile('b.pdf');
      await queue.add(a);
      await queue.add(b);
      await queue.add(a);
      expect((await queue.getFiles()).map((f) => f.path), [a.path, b.path]);
      expect(await queue.contains(b), isTrue);
    });

    test('removes files', () async {
      final queue = AutoUploadQueue(userId: 'user');
      final a = await createFile('a.pdf');
      await queue.add(a);
      await queue.remove(a);
      expect(await queue.getFiles(), isEmpty);
      expect(await queue.contains(a), isFalse);
    });

    test('drops files which do not exist anymore', () async {
      final queue = AutoUploadQueue(userId: 'user');
      final a = await createFile('a.pdf');
      final b = await createFile('b.pdf');
      await queue.add(a);
      await queue.add(b);
      await a.delete();
      expect((await queue.getFiles()).map((f) => f.path), [b.path]);
      expect(await queue.contains(a), isFalse);
    });

    test('is separate per user', () async {
      final a = await createFile('a.pdf');
      await const AutoUploadQueue(userId: 'user1').add(a);
      expect(await const AutoUploadQueue(userId: 'user2').getFiles(), isEmpty);
    });
  });

  group('PendingFilesAutoUploader', () {
    test('uploads all files and keeps failed ones queued', () async {
      final queue = AutoUploadQueue(userId: 'user');
      final a = await createFile('a.pdf');
      final b = await createFile('b.pdf');
      final c = await createFile('c.pdf');
      for (final file in [a, b, c]) {
        await queue.add(file);
      }
      final uploadedPaths = <String>[];
      final uploader = PendingFilesAutoUploader(
        getQueuedFiles: queue.getFiles,
        upload: (file) async {
          if (file.path == b.path) {
            throw Exception('Server error');
          }
          uploadedPaths.add(file.path);
          return file.path == a.path ? 'task-a' : null;
        },
        onUploaded: queue.remove,
      );

      final result = await uploader.uploadQueuedFiles();

      expect(result.uploaded, 2);
      expect(result.failed, 1);
      expect(result.taskIds, ['task-a']);
      expect(uploadedPaths, [a.path, c.path]);
      expect((await queue.getFiles()).map((f) => f.path), [b.path]);
    });

    test('ignores calls while an upload is running', () async {
      final a = await createFile('a.pdf');
      final completer = Completer<String?>();
      var uploads = 0;
      final uploader = PendingFilesAutoUploader(
        getQueuedFiles: () async => [a],
        upload: (_) {
          uploads++;
          return completer.future;
        },
        onUploaded: (_) async {},
      );

      final first = uploader.uploadQueuedFiles();
      final second = await uploader.uploadQueuedFiles();
      completer.complete('task');

      expect(second.uploaded, 0);
      expect((await first).uploaded, 1);
      expect(uploads, 1);
    });
  });
}
