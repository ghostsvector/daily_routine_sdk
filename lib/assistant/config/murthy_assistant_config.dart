/// Process-wide config for the subprocess-backed [AssistantService] and
/// [VoiceService] implementations (see `lib/assistant/implementations/`),
/// which drive a local clone of the `murthy-voice` Python project instead
/// of a compiled-in native library — see that repo's README for why
/// (self-hosted CPU-only LLM + TTS, no cloud API).
///
/// The composing app calls [configure] exactly once at startup, before
/// constructing any assistant/voice service.
class MurthyAssistantConfig {
  MurthyAssistantConfig._({
    required this.pythonExecutable,
    required this.murthyVoiceRepoPath,
  });

  static MurthyAssistantConfig? _current;

  /// [pythonExecutable] — path to the Python interpreter with
  /// `murthy-voice`'s `requirements.txt` installed (typically
  /// `<murthy-voice repo>/venv/bin/python`).
  ///
  /// [murthyVoiceRepoPath] — path to a local clone of
  /// github.com/ghostsvector/murthy-voice, containing
  /// `assistant_server.py` and `tts_server.py`.
  static void configure({
    required String pythonExecutable,
    required String murthyVoiceRepoPath,
  }) {
    _current = MurthyAssistantConfig._(
      pythonExecutable: pythonExecutable,
      murthyVoiceRepoPath: murthyVoiceRepoPath,
    );
  }

  static MurthyAssistantConfig get current =>
      _current ??
      (throw StateError(
        'MurthyAssistantConfig.configure() was never called. The composing '
        'app must call it once at startup before constructing any '
        'AssistantService/VoiceService implementation.',
      ));

  /// Whether [configure] has been called — lets UI hide the "Ask Murthy"
  /// affordance instead of erroring when it isn't available (not Linux
  /// desktop, or the composing app has no `murthy-voice` clone set up).
  static bool get isConfigured => _current != null;

  final String pythonExecutable;
  final String murthyVoiceRepoPath;
}
