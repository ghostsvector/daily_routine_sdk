/// One event from a [WakeWordService]'s listening loop.
sealed class WakeWordEvent {}

/// "Hey Murthy" was heard — the UI should show it's now listening for the
/// actual question/topic.
class WakeDetected extends WakeWordEvent {}

/// What was said after the wake word, ready to hand to [AssistantService].
class QueryTranscribed extends WakeWordEvent {
  QueryTranscribed(this.text);

  final String text;
}

/// A recoverable problem (e.g. nothing understood, a transcription hiccup)
/// — the listening loop keeps running after this.
class WakeWordError extends WakeWordEvent {
  WakeWordError(this.message);

  final String message;
}

/// Murthy's "Hey Murthy" wake word — listens continuously and reports back
/// when it hears the wake word, then what you said right after it.
///
/// No cloud speech API: implementations either run a real local wake-word
/// engine (Linux, via murthy-voice's `voice_trigger_server.py`) or
/// approximate one with the OS's own speech recognizer (Android — see
/// `AndroidSpeechWakeWordService`'s doc comment for why it's an
/// approximation, not a true always-on wake-word engine).
abstract class WakeWordService {
  /// Events as they happen. Only meaningful between [start] and [stop].
  Stream<WakeWordEvent> get events;

  /// Begins listening. Safe to call again while already listening (a
  /// no-op).
  Future<void> start();

  /// Stops listening. Safe to call when not listening.
  Future<void> stop();

  /// Releases whatever process/recognizer this implementation is holding
  /// open. Safe to call more than once.
  Future<void> dispose();
}
