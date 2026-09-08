import 'dart:convert';

import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/models/routine_task.dart';
import 'package:daily_routine_sdk/routines/implementations/rest_routine_repository_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _taskDoc(String id, String title, int startMinuteOfDay) {
  return {
    'name': 'projects/p/databases/(default)/documents/users/u/tasks/$id',
    'fields': {
      'title': {'stringValue': title},
      'startMinuteOfDay': {'integerValue': '$startMinuteOfDay'},
      'durationMinutes': {'integerValue': '30'},
    },
  };
}

void main() {
  RestFirebaseConfig.configure(projectId: 'p', apiKey: 'k');

  test('a new subscription after cancel gets the last-known value immediately', () async {
    var requestCount = 0;
    final mock = MockClient((request) async {
      requestCount++;
      return http.Response(
        jsonEncode({
          'documents': [_taskDoc('1', 'Run', 360)],
        }),
        200,
      );
    });

    final service = RestRoutineRepositoryService(
      client: mock,
      pollInterval: const Duration(minutes: 10), // long enough it won't fire during the test
    );

    final first = await service.watchTasks('u').first;
    expect(first, hasLength(1));
    expect(requestCount, 1);

    // Simulate a torn-down-and-recreated listener (e.g. Riverpod
    // .autoDispose losing then regaining its last subscriber) by listening
    // again after the first subscription's stream is done being awaited —
    // `.first` already cancelled it. The very next value emitted must be
    // the cached one, not a wait for a fresh network round-trip.
    final events = <List<RoutineTask>>[];
    final sub = service.watchTasks('u').listen(events.add);
    await Future<void>.delayed(Duration.zero); // let the sync cached emit land
    expect(events, isNotEmpty);
    expect(events.first.single.title, 'Run');

    await sub.cancel();
  });

  test('a successful write triggers an immediate refresh, not a wait for the next poll', () async {
    var requestCount = 0;
    final mock = MockClient((request) async {
      requestCount++;
      return http.Response(
        jsonEncode({
          'documents': [_taskDoc('1', 'Refreshed', 400)],
        }),
        200,
      );
    });

    final service = RestRoutineRepositoryService(
      client: mock,
      pollInterval: const Duration(minutes: 10),
    );

    final events = <List<RoutineTask>>[];
    final sub = service.watchTasks('u').listen(events.add);
    await Future<void>.delayed(Duration.zero);
    final countAfterFirstPoll = requestCount;

    await service.setTaskCompleted('u', '1', isCompleted: true);
    // setTaskCompleted's own PATCH, plus the immediate refresh poll it
    // triggers — not just the PATCH alone.
    await Future<void>.delayed(Duration.zero);
    expect(requestCount, greaterThan(countAfterFirstPoll + 1));

    await sub.cancel();
  });
}
