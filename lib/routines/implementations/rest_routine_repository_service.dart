import 'dart:async';
import 'dart:convert';

import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/error_classification.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/firestore_rest/firestore_rest_codec.dart';
import 'package:daily_routine_sdk/models/routine_task.dart';
import 'package:daily_routine_sdk/routines/routine_repository_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// [RoutineRepositoryService] backed directly by the Firestore REST API v1,
/// for platforms with no native `cloud_firestore` plugin implementation
/// (Linux desktop — see `FirestoreRoutineRepositoryService`, which
/// dispatches to this on Linux).
///
/// [watchTasks] has no true push channel available over plain REST —
/// Firestore's real-time Listen API is a bidirectional gRPC/HTTP2 stream,
/// not reasonably implementable with `package:http`. No background polling
/// either: this fetches once per [watchTasks] subscription (see
/// [_refreshNow] for how a write still shows up immediately) rather than on
/// a repeating timer — a timer here re-fetches the whole `tasks` collection
/// on every tick with no server-side limit, so it burns through Firestore's
/// free-tier daily read quota simply by running for 24h, independent of how
/// small the task list is.
class RestRoutineRepositoryService implements RoutineRepositoryService {
  RestRoutineRepositoryService({http.Client? client})
    : _client = client ?? http.Client();

  static const _logName = 'RestRoutineRepositoryService';

  final http.Client _client;

  final Map<String, StreamController<List<RoutineTask>>> _watchControllers = {};
  // Last successfully polled result per uid, kept around after the
  // controller itself is torn down (e.g. a `.autoDispose` Riverpod
  // provider losing its last listener when a screen closes). Riverpod
  // re-subscribing when the screen reopens would otherwise show nothing
  // while the fresh poll that subscription triggers is still in flight —
  // this caches so it shows the last-known list instantly instead.
  final Map<String, List<RoutineTask>> _lastKnown = {};

  String _baseUrl(String uid) =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents/'
      'users/$uid/tasks';

  Future<Map<String, String>> _headers() async {
    final token = await RestFirebaseConfig.current.idTokenProvider?.call();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  Stream<List<RoutineTask>> watchTasks(String uid) {
    final existing = _watchControllers[uid];
    if (existing != null) return existing.stream;

    late final StreamController<List<RoutineTask>> controller;
    controller = StreamController<List<RoutineTask>>.broadcast(
      onListen: () {
        final cached = _lastKnown[uid];
        if (cached != null) controller.add(cached);
        unawaited(_pollOnce(uid));
      },
      onCancel: () {
        _watchControllers.remove(uid);
      },
    );
    _watchControllers[uid] = controller;
    return controller.stream;
  }

  /// Triggers an out-of-band poll right now instead of waiting for the
  /// next scheduled tick — called after a write so its own effect is
  /// visible immediately rather than up to `pollInterval` later.
  void _refreshNow(String uid) {
    if (_watchControllers.containsKey(uid)) unawaited(_pollOnce(uid));
  }

  Future<void> _pollOnce(String uid) async {
    final controller = _watchControllers[uid];
    if (controller == null || controller.isClosed) return;
    try {
      debugPrint('[$_logName] Polling users/$uid/tasks');
      final response = await _client.get(
        Uri.parse(_baseUrl(uid)),
        headers: await _headers(),
      );
      if (response.statusCode != 200) {
        debugPrint('[$_logName] Poll failed: ${response.statusCode} ${response.body}');
        controller.addError(
          classifyFirestoreRestError(
            response.statusCode,
            response.body,
            operation: 'watchTasks',
          ),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = body['documents'] as List<dynamic>? ?? const [];
      debugPrint('[$_logName] Fetched ${docs.length} task doc(s)');
      final tasks = docs.map((doc) {
        final map = doc as Map<String, dynamic>;
        final id = (map['name'] as String).split('/').last;
        return RoutineTask.fromJson({...decodeFirestoreFields(map), 'id': id});
      }).toList()..sort((a, b) => a.startMinuteOfDay.compareTo(b.startMinuteOfDay));
      _lastKnown[uid] = tasks;
      controller.add(tasks);
    } catch (e, stackTrace) {
      debugPrint('[$_logName] Poll threw: $e');
      controller.addError(e, stackTrace);
    }
  }

  @override
  Future<Result<void>> upsertTask(String uid, RoutineTask task) async {
    try {
      final now = DateTime.now();
      final data =
          task.copyWith(updatedAt: now, createdAt: task.createdAt ?? now).toJson()
            ..remove('id');
      final response = await _client.patch(
        Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(task.id)}'),
        headers: await _headers(),
        body: jsonEncode({'fields': encodeFirestoreFields(data)}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Result.failure(
          classifyFirestoreRestError(
            response.statusCode,
            response.body,
            operation: 'upsertTask',
          ),
        );
      }
      _refreshNow(uid);
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> deleteTask(String uid, String taskId) async {
    try {
      final response = await _client.delete(
        Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(taskId)}'),
        headers: await _headers(),
      );
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        return Result.failure(
          classifyFirestoreRestError(
            response.statusCode,
            response.body,
            operation: 'deleteTask',
          ),
        );
      }
      _refreshNow(uid);
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> setTaskCompleted(
    String uid,
    String taskId, {
    required bool isCompleted,
  }) async {
    try {
      final fields = encodeFirestoreFields({
        'isCompletedToday': isCompleted,
        'completedDate': isCompleted ? RoutineTask.todayKey() : null,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      final uri = Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(taskId)}').replace(
        queryParameters: {
          'updateMask.fieldPaths': ['isCompletedToday', 'completedDate', 'updatedAt'],
        },
      );
      final response = await _client.patch(
        uri,
        headers: await _headers(),
        body: jsonEncode({'fields': fields}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Result.failure(
          classifyFirestoreRestError(
            response.statusCode,
            response.body,
            operation: 'setTaskCompleted',
          ),
        );
      }
      _refreshNow(uid);
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }
}
