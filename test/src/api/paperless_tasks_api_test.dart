import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/paperless_api.dart';

/// Answers every request with the next response produced by [_responses].
class _FakeAdapter implements HttpClientAdapter {
  final Object? Function(RequestOptions options) _responses;
  final List<RequestOptions> requests = [];

  _FakeAdapter(this._responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(_responses(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _task(String status, {Object? relatedDocument}) => {
  'id': 1,
  'task_id': 'abc',
  'task_file_name': 'scan.pdf',
  'task_name': 'consume_file',
  'type': 'auto_task',
  'status': status,
  'result': null,
  'acknowledged': false,
  'related_document': relatedDocument,
};

PaperlessTasksApi _api(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://paperless.example'))
    ..httpClientAdapter = adapter;
  return PaperlessTasksApiImpl(dio);
}

void main() {
  test('findByTaskId parses the (unpaginated) list response', () async {
    final adapter = _FakeAdapter(
      (_) => [_task('SUCCESS', relatedDocument: 42)],
    );
    final task = await _api(adapter).findByTaskId('abc');
    expect(task?.status, StatusEnum.success);
    expect(task?.relatedDocumentId, 42);
    expect(adapter.requests.single.queryParameters['task_id'], 'abc');
  });

  test('findByTaskId supports paginated responses', () async {
    final adapter = _FakeAdapter(
      (_) => {
        'count': 1,
        'results': [_task('PENDING', relatedDocument: '7')],
      },
    );
    final task = await _api(adapter).findByTaskId('abc');
    expect(task?.status, StatusEnum.pending);
    expect(task?.relatedDocumentId, 7);
  });

  test('findByTaskId returns null for unknown tasks', () async {
    final adapter = _FakeAdapter((_) => []);
    expect(await _api(adapter).findByTaskId('abc'), isNull);
  });

  test('listenForTaskChanges emits status changes until finished', () {
    fakeAsync((async) {
      final responses = <Object>[
        [], // Task not created yet.
        [_task('PENDING')],
        [_task('PENDING')],
        [_task('STARTED')],
        [_task('SUCCESS', relatedDocument: 3)],
      ];
      var call = 0;
      final adapter = _FakeAdapter((_) => responses[call++]);
      final statuses = <StatusEnum?>[];
      var done = false;
      _api(adapter)
          .listenForTaskChanges('abc')
          .listen(
            (task) => statuses.add(task.status),
            onDone: () => done = true,
          );
      async.elapse(const Duration(minutes: 1));
      expect(statuses, [
        StatusEnum.pending,
        StatusEnum.started,
        StatusEnum.success,
      ]);
      expect(done, isTrue);
      expect(call, responses.length);
    });
  });

  test('listenForTaskChanges fails if the task never shows up', () {
    fakeAsync((async) {
      final adapter = _FakeAdapter((_) => []);
      Object? error;
      _api(
        adapter,
      ).listenForTaskChanges('abc').listen((_) {}, onError: (e) => error = e);
      async.elapse(const Duration(minutes: 2));
      expect(error, isNotNull);
    });
  });
}
