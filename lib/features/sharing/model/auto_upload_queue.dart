import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Keeps track of pending files which could not be uploaded because the device
/// was offline, and which should be uploaded automatically once it is back
/// online.
///
/// Other pending files (e.g. files the user decided to keep instead of
/// uploading them right away) are not part of this queue.
class AutoUploadQueue {
  final String userId;

  const AutoUploadQueue({required this.userId});

  String get _key => 'autoUploadQueue_$userId';

  Future<void> add(File file) async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_key) ?? [];
    if (!paths.contains(file.path)) {
      await prefs.setStringList(_key, [...paths, file.path]);
    }
  }

  Future<void> remove(File file) async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_key) ?? [];
    if (paths.contains(file.path)) {
      await prefs.setStringList(
        _key,
        paths.where((path) => path != file.path).toList(),
      );
    }
  }

  Future<bool> contains(File file) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).contains(file.path);
  }

  /// Returns the queued files in the order they were added. Files which do not
  /// exist anymore are removed from the queue.
  Future<List<File>> getFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_key) ?? [];
    final existingPaths = [
      for (final path in paths)
        if (await File(path).exists()) path,
    ];
    if (existingPaths.length != paths.length) {
      await prefs.setStringList(_key, existingPaths);
    }
    return existingPaths.map(File.new).toList();
  }
}
