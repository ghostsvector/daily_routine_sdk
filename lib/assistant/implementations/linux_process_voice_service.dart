import 'package:daily_routine_sdk/assistant/config/murthy_assistant_config.dart';
import 'package:daily_routine_sdk/assistant/implementations/json_line_process.dart';
import 'package:daily_routine_sdk/assistant/voice_service.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:path/path.dart' as p;

/// [VoiceService] backed by a local `murthy-voice` clone's
/// `tts_server.py`, kept running as a long-lived subprocess (model load
/// time is several seconds — too slow to pay per request) and driven over
/// stdin/stdout, no network socket. Playback happens inside the Python
/// process itself (via `aplay`), so this class has no audio pipeline of
/// its own — [speak] just waits for the "done" response.
///
/// Linux desktop only for now — see
/// `lib/assistant/config/murthy_assistant_config.dart` for setup and why
/// a subprocess instead of, say, `flutter_tts`: the custom Telugu+English
/// MMS voices already built and proven in `murthy-voice` beat relying on
/// whatever (if any) system TTS happens to be installed on a Linux desktop.
class LinuxProcessVoiceService implements VoiceService {
  JsonLineProcess? _process;

  Future<JsonLineProcess> _ensureStarted() async {
    final existing = _process;
    if (existing != null) return existing;
    final config = MurthyAssistantConfig.current;
    final started = await JsonLineProcess.start(
      config.pythonExecutable,
      [p.join(config.murthyVoiceRepoPath, 'tts_server.py')],
      workingDirectory: config.murthyVoiceRepoPath,
    );
    _process = started;
    return started;
  }

  @override
  Future<Result<void>> speak(String text, {required String languageCode}) async {
    try {
      final process = await _ensureStarted();
      final response = await process.request({'text': text, 'lang': languageCode});
      final error = response['error'];
      if (error != null) {
        return Result.failure(AssistantError(error.toString()));
      }
      return const Result.success(null);
    } catch (e, stackTrace) {
      // A crashed subprocess shouldn't keep failing every call after —
      // drop it so the next speak() respawns it.
      _process = null;
      return Result.failure(
        AssistantError(
          'Murthy voice unavailable.',
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
