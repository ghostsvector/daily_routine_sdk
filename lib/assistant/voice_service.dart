import 'package:daily_routine_sdk/error/result.dart';

/// Murthy's voice — speaks text aloud in a given language, locally, no
/// cloud TTS API.
abstract class VoiceService {
  /// Speaks [text] in [languageCode] (e.g. `'te'`, `'en'`). Completes once
  /// playback has finished.
  Future<Result<void>> speak(String text, {required String languageCode});

  /// Releases whatever process/model this implementation is holding open.
  /// Safe to call more than once.
  Future<void> dispose();
}
