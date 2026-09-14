import 'package:daily_routine_sdk/error/result.dart';

/// Murthy's "brain" — explains a topic from a local LLM's own pretrained
/// knowledge (no cloud API, no fine-tuning, no retrieval). See
/// `murthy-voice`'s README for why: the "self-hosted, no GPU" constraint
/// rules out anything but a small model run locally.
abstract class AssistantService {
  /// Returns a spoken-friendly explanation of [topic] (plain sentences, no
  /// markdown — the caller typically hands this straight to a
  /// [VoiceService]).
  Future<Result<String>> explain(String topic);

  /// Releases whatever process/model this implementation is holding open.
  /// Safe to call more than once.
  Future<void> dispose();
}
