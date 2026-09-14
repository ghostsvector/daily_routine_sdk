import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A local subprocess speaking one-JSON-object-per-line on stdin/stdout
/// (see murthy-voice's `assistant_server.py` / `tts_server.py`). No
/// network socket — just a pipe to a process this Dart code owns.
///
/// The protocol has no request IDs, so concurrent [request] calls are
/// serialized: a call made while another is in flight waits for it to
/// finish first, rather than risk reading another call's response line.
class JsonLineProcess {
  JsonLineProcess._(this._process, this._lines);

  final Process _process;
  final StreamIterator<String> _lines;
  Future<void> _queue = Future.value();

  static Future<JsonLineProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    final lines = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    // First line is the {"ready": true} handshake the server script
    // writes on startup, once its model is loaded — consumed here so
    // callers only ever see request/response lines.
    if (!await lines.moveNext()) {
      throw StateError(
        '$executable ${arguments.join(' ')} exited before signaling ready',
      );
    }
    return JsonLineProcess._(process, lines);
  }

  /// Sends [payload] as one JSON line and returns the next JSON line back.
  Future<Map<String, dynamic>> request(Map<String, dynamic> payload) {
    final previous = _queue;
    final result = previous.then((_) async {
      _process.stdin.writeln(jsonEncode(payload));
      if (!await _lines.moveNext()) {
        throw StateError('Subprocess closed its output unexpectedly');
      }
      return jsonDecode(_lines.current) as Map<String, dynamic>;
    });
    // Chain the next call off this one regardless of success/failure, but
    // don't let a failed request propagate into an unrelated caller.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> dispose() async {
    await _process.stdin.close();
    _process.kill();
  }
}
