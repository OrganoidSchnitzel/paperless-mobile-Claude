import 'dart:async';

import 'package:flutter/material.dart';
import 'package:paperless_mobile/api/paperless_api.dart';

class PendingTasksNotifier extends ValueNotifier<Map<String, TasksView>> {
  final PaperlessTasksApi _api;

  final Map<String, StreamSubscription> _subscriptions = {};

  PendingTasksNotifier(this._api) : super({});

  @override
  void dispose() {
    stopListeningToTaskChanges();
    super.dispose();
  }

  /// Whether the task with the given [taskId] is currently being tracked.
  bool isTracking(String taskId) => _subscriptions.containsKey(taskId);

  void listenToTaskChanges(String taskId) {
    if (isTracking(taskId)) {
      return;
    }
    _subscriptions[taskId] = _api
        .listenForTaskChanges(taskId)
        .listen(
          (task) {
            value = {...value, taskId: task};
          },
          onError: (_) => _onTrackingStopped(taskId),
          onDone: () => _onTrackingStopped(taskId),
          cancelOnError: true,
        );
  }

  void _onTrackingStopped(String taskId) {
    _subscriptions.remove(taskId);
    value = {...value}..remove(taskId);
  }

  void stopListeningToTaskChanges([String? taskId]) {
    if (taskId != null) {
      _subscriptions[taskId]?.cancel();
      _subscriptions.remove(taskId);
    } else {
      for (var sub in _subscriptions.values) {
        sub.cancel();
      }
      _subscriptions.clear();
    }
  }

  Future<void> acknowledgeTasks(Iterable<String> taskIds) async {
    final tasks = value.values.where((task) => taskIds.contains(task.taskId));
    await Future.wait([
      for (var task in tasks) _api.acknowledgeTasks([task.id]),
    ]);
    value = value..removeWhere((key, value) => taskIds.contains(key));
    notifyListeners();
  }
}
