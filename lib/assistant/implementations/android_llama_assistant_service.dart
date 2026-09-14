import 'dart:io';

import 'package:daily_routine_sdk/assistant/assistant_service.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:http/http.dart' as http;
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// [AssistantService] backed by a local Qwen3-1.7B GGUF model — same model
/// as `murthy-voice`'s `llm.py` — run on-device via `llama_cpp_dart`'s
/// isolate-managed `LlamaParent`, CPU only (`nGpuLayers = 0`).
///
/// Verified against `llama_cpp_dart` 0.2.2's actual published source (the
/// package's pub.dev-hosted archive, read directly — its README/doc-comment
/// examples turned out to lag the real API in places). `LlamaParent.stream`
/// emits raw text chunks for whichever prompt is currently running;
/// `LlamaParent.completions` emits one [CompletionEvent] per finished
/// prompt, keyed by the prompt id `sendPrompt` returns.
///
/// Still unverified: this hasn't been built/run on an actual Android
/// device (no Flutter/Android toolchain available), and `nGpuLayers = 0`'s
/// CPU-only Android performance for a 1.7B model is untested — llama.cpp's
/// Dart FFI binding itself compiles as part of the app's normal Android
/// Gradle build (this package ships as a Flutter plugin with its own
/// native module), not something handled here.
///
/// Downloads the model (~1.1GB) into app support storage on first use —
/// too large to bundle as a Flutter asset. Every call after that first
/// download is fully offline, same as murthy-voice's own `download_model.py`.
class AndroidLlamaAssistantService implements AssistantService {
  static const _modelUrl =
      'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf';
  static const _modelFileName = 'Qwen3-1.7B-Q4_K_M.gguf';

  // Mirrors murthy-voice's llm.py SYSTEM_PROMPT — see that file for the
  // reasoning behind each constraint.
  static const _systemPrompt =
      'You are Murthy, a patient, thorough personal professor. The user has '
      'forgotten or never learned the topic they ask about. Explain it from '
      'the basics, clearly and in some depth, the way a good teacher would — '
      'not a one-line dictionary answer. Reply in the same language the user '
      'asked in (Telugu or English). Keep the explanation spoken-friendly: '
      'plain sentences, no markdown, no bullet lists, no code blocks, since '
      'it will be read aloud by a text-to-speech voice.';

  LlamaParent? _parent;
  // The protocol has no natural request queue of its own at this level
  // (sendPrompt() itself queues internally, but stream/completions are
  // shared across whatever prompt is currently in flight), so concurrent
  // explain() calls are serialized the same way JsonLineProcess does it.
  Future<void> _queue = Future.value();

  Future<String> _ensureModelDownloaded() async {
    final supportDir = await getApplicationSupportDirectory();
    final modelPath = p.join(supportDir.path, 'models', _modelFileName);
    final file = File(modelPath);
    if (await file.exists()) return modelPath;

    await file.parent.create(recursive: true);
    final response = await http.Client().send(
      http.Request('GET', Uri.parse(_modelUrl)),
    );
    if (response.statusCode != 200) {
      throw StateError('Model download failed: HTTP ${response.statusCode}');
    }
    final sink = file.openWrite();
    await response.stream.pipe(sink);
    await sink.close();
    return modelPath;
  }

  Future<LlamaParent> _ensureParent() async {
    final existing = _parent;
    if (existing != null) return existing;
    final modelPath = await _ensureModelDownloaded();
    final loadCommand = LlamaLoad(
      path: modelPath,
      modelParams: ModelParams()..nGpuLayers = 0,
      contextParams: ContextParams()..nCtx = 4096,
      samplingParams: SamplerParams(),
    );
    final parent = LlamaParent(loadCommand, ChatMLFormat());
    await parent.init();
    _parent = parent;
    return parent;
  }

  @override
  Future<Result<String>> explain(String topic) {
    final previous = _queue;
    final result = previous.then((_) => _explainNow(topic));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Result<String>> _explainNow(String topic) async {
    try {
      final parent = await _ensureParent();
      parent.messages = [
        {'role': 'system', 'content': _systemPrompt},
        // /no_think: Qwen3's documented switch to skip its reasoning trace
        // and answer directly — see llm.py's module docstring for why.
        {'role': 'user', 'content': '$topic /no_think'},
      ];

      final buffer = StringBuffer();
      final subscription = parent.stream.listen(buffer.write);
      try {
        final promptId = await parent.sendPrompt(topic);
        final event = await parent.completions.firstWhere(
          (e) => e.promptId == promptId,
        );
        if (!event.success) {
          return Result.failure(
            AssistantError(event.errorDetails ?? 'Generation failed.'),
          );
        }
        return Result.success(buffer.toString().trim());
      } finally {
        await subscription.cancel();
      }
    } catch (e, stackTrace) {
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
    final parent = _parent;
    _parent = null;
    await parent?.dispose();
  }
}
