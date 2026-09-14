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
/// isolate engine (CPU only: `gpuLayers: 0`).
///
/// **Unverified.** Written against `llama_cpp_dart` 0.2.2's source
/// (`LlamaEngine`/`EngineChat`/`GenerationEvent` — the package went
/// through breaking API changes in 0.2.0, and some published docs still
/// show an older `LlamaParent`/`LlamaLoad` API), without a Flutter/Android
/// toolchain available to actually build and run this. Confirm this
/// compiles against whatever version resolves, and adjust class/method
/// names if the installed API differs, before relying on it.
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

  LlamaEngine? _engine;

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

  Future<LlamaEngine> _ensureEngine() async {
    final existing = _engine;
    if (existing != null) return existing;
    final modelPath = await _ensureModelDownloaded();
    final engine = await LlamaEngine.spawn(
      modelParams: ModelParams(path: modelPath, gpuLayers: 0),
      contextParams: const ContextParams(nCtx: 4096),
    );
    _engine = engine;
    return engine;
  }

  @override
  Future<Result<String>> explain(String topic) async {
    try {
      final engine = await _ensureEngine();
      final chat = await engine.createChat();
      chat.addSystem(_systemPrompt);
      // /no_think: Qwen3's documented switch to skip its reasoning trace
      // and answer directly — see llm.py's module docstring for why.
      chat.addUser('$topic /no_think');

      final buffer = StringBuffer();
      await for (final event in chat.generate(maxTokens: 512)) {
        switch (event) {
          case TokenEvent(text: final text):
            buffer.write(text);
          case DoneEvent(trailingText: final trailing):
            buffer.write(trailing);
          default:
            break;
        }
      }
      await chat.dispose();
      return Result.success(buffer.toString().trim());
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
    // LlamaEngine's own shutdown method wasn't confirmed against the
    // installed package version (see class doc comment) — dropping the
    // reference here at minimum stops this service from reusing a stale
    // engine, but may leak the isolate/model until process exit. Wire up
    // the real dispose/shutdown call once confirmed.
    _engine = null;
  }
}
