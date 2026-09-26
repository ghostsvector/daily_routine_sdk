import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:daily_routine_sdk/assistant/config/murthy_assistant_config.dart';
import 'package:daily_routine_sdk/assistant/wake_word_service.dart';
import 'package:path/path.dart' as p;

/// [WakeWordService] backed by a local `murthy-voice` clone's
/// `voice_trigger_server.py` — a real wake-word engine (openWakeWord) plus
/// local speech-to-text (faster-whisper), spawned as a subprocess whose
/// stdout is a push stream of JSON events (`{"event": "wake"}`,
/// `{"event": "transcript", "text": "..."}`) — no network socket, no
/// request/response protocol needed since it drives itself off the
/// microphone. See `MurthyAssistantConfig`'s doc comment for setup.
///
/// Linux desktop only — see murthy-voice's README for why Android takes a
/// different path ([AndroidSpeechWakeWordService]).
class LinuxProcessWakeWordService implements WakeWordService {
  Process? _process;
  StreamSubscription<String>? _subscription;
  final StreamController<WakeWordEvent> _controller =
      StreamController<WakeWordEvent>.broadcast();

  @override
  Stream<WakeWordEvent> get events => _controller.stream;

  @override
  Future<void> start() async {
    if (_process != null) return;
    final config = MurthyAssistantConfig.current;
    final process = await Process.start(
      config.pythonExecutable,
      [p.join(config.murthyVoiceRepoPath, 'voice_trigger_server.py')],
      workingDirectory: config.murthyVoiceRepoPath,
    );
    _process = process;
    _subscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: (Object e) => _controller.add(WakeWordError('$e')),
        );
  }

  void _handleLine(String line) {
    if (line.isEmpty) return;
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (data['event']) {
      case 'wake':
        _controller.add(WakeDetected());
      case 'transcript':
        final text = data['text'];
        if (text is String && text.isNotEmpty) {
          _controller.add(QueryTranscribed(text));
        }
      case 'error':
        _controller.add(
          WakeWordError((data['message'] as String?) ?? 'Unknown error.'),
        );
      // 'ready' is just a startup signal — nothing to surface for it.
    }
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    final process = _process;
    _process = null;
    if (process != null) {
      await process.stdin.close();
      process.kill();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
