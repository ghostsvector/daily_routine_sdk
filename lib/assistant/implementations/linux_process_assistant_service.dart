import 'package:daily_routine_sdk/assistant/assistant_service.dart';
import 'package:daily_routine_sdk/assistant/config/murthy_assistant_config.dart';
import 'package:daily_routine_sdk/assistant/implementations/json_line_process.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:path/path.dart' as p;

/// [AssistantService] backed by a local `murthy-voice` clone's
/// `assistant_server.py`, kept running as a long-lived subprocess (model
/// load time is several seconds — too slow to pay per request) and driven
/// over stdin/stdout, no network socket. See
/// `lib/assistant/config/murthy_assistant_config.dart` for setup.
///
/// Linux desktop only for now — see that config file's doc comment for
/// why a subprocess instead of a compiled-in native LLM library.
class LinuxProcessAssistantService implements AssistantService {
  JsonLineProcess? _process;

  Future<JsonLineProcess> _ensureStarted() async {
    final existing = _process;
    if (existing != null) return existing;
    final config = MurthyAssistantConfig.current;
    final started = await JsonLineProcess.start(
      config.pythonExecutable,
      [p.join(config.murthyVoiceRepoPath, 'assistant_server.py')],
      workingDirectory: config.murthyVoiceRepoPath,
    );
    _process = started;
    return started;
  }

  @override
  Future<Result<String>> explain(String topic) async {
    try {
      final process = await _ensureStarted();
      final response = await process.request({'topic': topic});
      final error = response['error'];
      if (error != null) {
        return Result.failure(AssistantError(error.toString()));
      }
      return Result.success(response['text'] as String);
    } catch (e, stackTrace) {
      // A crashed subprocess shouldn't keep failing every call after —
      // drop it so the next explain() respawns it.
      _process = null;
      return Result.failure(
        AssistantError(
          'Murthy brain unavailable.',
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    final process = _process;
    _process = null;
    await process?.dispose();
  }
}
