import 'dart:async';
import 'dart:convert';

import 'package:daily_routine_sdk/blocked_apps/blocked_apps_repository_service.dart';
import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/firestore_rest/firestore_rest_codec.dart';
import 'package:daily_routine_sdk/models/blocked_app.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// [BlockedAppsRepositoryService] backed directly by the Firestore REST API
/// v1, for platforms with no native `cloud_firestore` plugin implementation
/// (Linux desktop — see `FirestoreBlockedAppsRepositoryService`, which
/// dispatches to this on Linux). No background polling — see
/// `RestRoutineRepositoryService`'s doc comment for why.
class RestBlockedAppsRepositoryService implements BlockedAppsRepositoryService {
  RestBlockedAppsRepositoryService({http.Client? client})
    : _client = client ?? http.Client();

  static const _logName = 'RestBlockedAppsRepositoryService';

  final http.Client _client;

  final Map<String, StreamController<List<BlockedApp>>> _watchControllers = {};
  // See RestRoutineRepositoryService's identical field for why this exists:
  // instant last-known data for a re-subscribing (e.g. autoDispose-torn-down)
  // listener instead of a wait for the fresh poll to complete.
  final Map<String, List<BlockedApp>> _lastKnown = {};

  String _baseUrl(String uid) =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents/'
      'users/$uid/blockedApps';

  Future<Map<String, String>> _headers() async {
    final token = await RestFirebaseConfig.current.idTokenProvider?.call();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  Stream<List<BlockedApp>> watchBlockedApps(String uid) {
    final existing = _watchControllers[uid];
    if (existing != null) return existing.stream;

    late final StreamController<List<BlockedApp>> controller;
    controller = StreamController<List<BlockedApp>>.broadcast(
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

  /// See RestRoutineRepositoryService's identical method.
  void _refreshNow(String uid) {
    if (_watchControllers.containsKey(uid)) unawaited(_pollOnce(uid));
  }

  Future<void> _pollOnce(String uid) async {
    final controller = _watchControllers[uid];
    if (controller == null || controller.isClosed) return;
    try {
      debugPrint('[$_logName] Polling users/$uid/blockedApps');
      final response = await _client.get(
        Uri.parse(_baseUrl(uid)),
        headers: await _headers(),
      );
      if (response.statusCode != 200) {
        debugPrint('[$_logName] Poll failed: ${response.statusCode} ${response.body}');
        controller.addError(
          StateError(
            'Firestore REST watchBlockedApps failed: ${response.statusCode} ${response.body}',
          ),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = body['documents'] as List<dynamic>? ?? const [];
      debugPrint('[$_logName] Fetched ${docs.length} blocked-app doc(s)');
      final apps = docs
          .map((doc) => BlockedApp.fromJson(decodeFirestoreFields(doc as Map<String, dynamic>)))
          .toList();
      _lastKnown[uid] = apps;
      controller.add(apps);
    } catch (e, stackTrace) {
      debugPrint('[$_logName] Poll threw: $e');
      controller.addError(e, stackTrace);
    }
  }

  @override
  Future<Result<void>> setBlockedApps(String uid, List<BlockedApp> apps) async {
    try {
      for (final app in apps) {
        final response = await _client.patch(
          Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(app.packageId)}'),
          headers: await _headers(),
          body: jsonEncode({'fields': encodeFirestoreFields(app.toJson())}),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return Result.failure(
            DatabaseError(
              'Firestore REST setBlockedApps failed: ${response.statusCode} ${response.body}',
            ),
          );
        }
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
  Future<Result<void>> removeBlockedApp(String uid, String packageId) async {
    try {
      final response = await _client.delete(
        Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(packageId)}'),
        headers: await _headers(),
      );
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        return Result.failure(
          DatabaseError(
            'Firestore REST removeBlockedApp failed: ${response.statusCode} ${response.body}',
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
