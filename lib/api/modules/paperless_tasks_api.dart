import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:paperless_mobile/api/models/models.dart';
import 'package:paperless_mobile/api/extensions/extensions.dart';
import 'package:paperless_mobile/api/utils/request_utils.dart';

abstract class PaperlessTasksApi {
  Future<TasksView?> find(int id);
  Future<Iterable<TasksView>> findAll([TaskFilterOptions options]);

  /// Returns the task with the given celery [taskId], or null if the server
  /// does not know (yet) about the task.
  Future<TasksView?> findByTaskId(String taskId);

  /// Periodically polls the task with the given celery [taskId] and emits the
  /// task whenever its status changes. The stream completes once the task has
  /// finished (successfully or not).
  Stream<TasksView> listenForTaskChanges(String taskId);
  Future<void> acknowledgeTasks(Iterable<int> tasks);
}

class PaperlessTasksApiImpl implements PaperlessTasksApi {
  final Dio _client;

  PaperlessTasksApiImpl(this._client);

  @override
  Future<TasksView?> find(int id) async {
    return getSingleResult(
      '/api/tasks/$id',
      TasksView.fromJson,
      ErrorCode.loadTasksError,
      client: _client,
    );
  }

  @override
  Future<Iterable<TasksView>> findAll([
    TaskFilterOptions options = const TaskFilterOptions(),
  ]) {
    return _getTasks(options.toJson());
  }

  @override
  Future<TasksView?> findByTaskId(String taskId) async {
    final tasks = await _getTasks({'task_id': taskId});
    return tasks.where((task) => task.taskId == taskId).firstOrNull;
  }

  /// The tasks endpoint is not paginated (it returns a plain list), but
  /// paginated responses are handled as well to be on the safe side.
  Future<List<TasksView>> _getTasks(Map<String, dynamic> queryParams) async {
    try {
      final response = await _client.get(
        '/api/tasks/',
        queryParameters: queryParams,
        options: Options(validateStatus: (status) => status == 200),
      );
      final data = response.data;
      final List<dynamic> results = switch (data) {
        List<dynamic> list => list,
        Map<String, dynamic> map => map['results'] as List<dynamic>? ?? [],
        _ => [],
      };
      return results
          .cast<Map<String, dynamic>>()
          .map(TasksView.fromJson)
          .toList();
    } on DioException catch (exception) {
      throw exception.unravel(
        orElse: const PaperlessApiException(ErrorCode.loadTasksError),
      );
    }
  }

  @override
  Stream<TasksView> listenForTaskChanges(String taskId) async* {
    // Number of polls without finding the task until we give up. The task is
    // usually created by the server right away, but this is not guaranteed.
    const maxPollsWithoutTask = 15;
    // Number of consecutive failed requests until we give up.
    const maxConsecutiveErrors = 5;

    int pollsWithoutTask = 0;
    int consecutiveErrors = 0;
    int polls = 0;
    StatusEnum? lastStatus;
    while (true) {
      if (polls > 0) {
        // Processing (e.g. OCR) can take a while, so poll less frequently
        // after the first minute.
        await Future.delayed(Duration(seconds: polls < 30 ? 2 : 5));
      }
      polls++;
      final TasksView? task;
      try {
        task = await findByTaskId(taskId);
        consecutiveErrors = 0;
      } catch (error) {
        if (++consecutiveErrors >= maxConsecutiveErrors) {
          rethrow;
        }
        continue;
      }
      if (task == null) {
        if (++pollsWithoutTask >= maxPollsWithoutTask) {
          throw Exception("Task with taskId $taskId does not exist.");
        }
        continue;
      }
      if (task.status != lastStatus || lastStatus == null) {
        log("Task ${task.taskId} (${task.id}) changed status: ${task.status}");
        lastStatus = task.status;
        yield task;
      }
      if (task.isFinished) {
        return;
      }
    }
  }

  @override
  Future<void> acknowledgeTasks(Iterable<int> tasks) async {
    try {
      final response = await _client.post(
        "/api/acknowledge_tasks/",
        data: {'tasks': tasks.toList()},
        options: Options(validateStatus: (status) => status == 200),
      );
      final acknowledgedTaskCount = AcknowledgeTasks.fromJson(
        response.data,
      ).result;
      if (acknowledgedTaskCount != tasks.length) {
        throw const PaperlessApiException(ErrorCode.acknowledgeTasksError);
      }
    } on DioException catch (exception) {
      throw exception.unravel(
        orElse: const PaperlessApiException(ErrorCode.acknowledgeTasksError),
      );
    }
  }
}
