import 'package:daily_routine_sdk/assistant/voice_service.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// [VoiceService] backed by the platform's built-in TTS engine via
/// `flutter_tts` — used on Android, where the OS's own TTS engine
/// (Google's, on most devices) is a reasonable default and needs no model
/// download or native build of our own. Telugu quality depends on whatever
/// voice pack the device has installed; unlike
/// [LinuxProcessVoiceService]'s custom MMS voices, there's no fallback if
/// the OS doesn't have a decent Telugu voice.
class FlutterTtsVoiceService implements VoiceService {
  final FlutterTts _tts = FlutterTts();
  bool _awaitConfigured = false;

  Future<void> _ensureConfigured() async {
    if (_awaitConfigured) return;
    // Makes `speak()` complete only once playback finishes, instead of
    // firing and returning immediately — needed so callers can rely on
    // `speak()`'s Future for "done speaking".
    await _tts.awaitSpeakCompletion(true);
    _awaitConfigured = true;
  }

  @override
  Future<Result<void>> speak(String text, {required String languageCode}) async {
    try {
      await _ensureConfigured();
      final locale = languageCode == 'te' ? 'te-IN' : 'en-US';
      await _tts.setLanguage(locale);
      final status = await _tts.speak(text);
      // flutter_tts's documented convention: 1 on success, 0/other on
      // failure (exact failure codes vary by platform).
      if (status != 1) {
        return Result.failure(
          AssistantError('TTS engine declined to speak (status $status).'),
        );
      }
      return const Result.success(null);
    } catch (e, stackTrace) {
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
    await _tts.stop();
  }
}
