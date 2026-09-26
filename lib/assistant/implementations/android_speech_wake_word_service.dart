import 'dart:async';

import 'package:daily_routine_sdk/assistant/wake_word_service.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// [WakeWordService] approximation for Android: there is no always-on
/// wake-word engine wired up here (openWakeWord, used on Linux, has no
/// Android/Flutter binding — see murthy-voice's README). Instead this
/// keeps the OS's own speech recognizer running continuously and watches
/// for "murthy" in what it hears, then listens again for the actual
/// question. Less power-efficient than a real wake-word model — every
/// listen session runs full speech recognition, not a lightweight
/// keyword-spotting net — but built on `speech_to_text`, a stable,
/// verified package API, rather than a guessed native binding.
class AndroidSpeechWakeWordService implements WakeWordService {
  final SpeechToText _stt = SpeechToText();
  final StreamController<WakeWordEvent> _controller =
      StreamController<WakeWordEvent>.broadcast();

  bool _running = false;
  bool _awaitingQuery = false;

  @override
  Stream<WakeWordEvent> get events => _controller.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    final available = await _stt.initialize(
      onStatus: _onStatus,
      onError: (error) => _controller.add(WakeWordError(error.errorMsg)),
    );
    if (!available) {
      _controller.add(
        WakeWordError('Speech recognition unavailable on this device.'),
      );
      return;
    }
    _running = true;
    _awaitingQuery = false;
    _listenForWake();
  }

  void _listenForWake() {
    if (!_running) return;
    _stt.listen(
      onResult: _onWakeResult,
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 55),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
      ),
    );
  }

  void _onWakeResult(SpeechRecognitionResult result) {
    if (!result.recognizedWords.toLowerCase().contains('murthy')) return;
    _controller.add(WakeDetected());
    _awaitingQuery = true;
    unawaited(_stt.stop());
  }

  void _listenForQuery() {
    if (!_running) return;
    _stt.listen(
      onResult: _onQueryResult,
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 2),
        partialResults: false,
      ),
    );
  }

  void _onQueryResult(SpeechRecognitionResult result) {
    if (!result.finalResult) return;
    final text = result.recognizedWords.trim();
    if (text.isNotEmpty) {
      _controller.add(QueryTranscribed(text));
    } else {
      _controller.add(WakeWordError("Didn't catch that — no transcript."));
    }
    _awaitingQuery = false;
    unawaited(_stt.stop());
  }

  // Each listen() call is time-limited by the OS (Android especially), so
  // this loops back into whichever phase (wake / query) we're in whenever
  // a session ends — that's what makes it "always listening".
  void _onStatus(String status) {
    if (!_running) return;
    if (status != 'notListening' && status != 'done') return;
    if (_awaitingQuery) {
      _listenForQuery();
    } else {
      _listenForWake();
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    _awaitingQuery = false;
    await _stt.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
