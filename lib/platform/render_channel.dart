import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

sealed class RenderEvent {
  const RenderEvent();
}

class RenderProgress extends RenderEvent {
  const RenderProgress(this.percent);
  final int percent;
}

class RenderDone extends RenderEvent {
  const RenderDone({required this.path, required this.sizeBytes, required this.durationMs, required this.height});
  final String path;
  final int sizeBytes;
  final int durationMs;
  final int height;
}

class RenderFailed extends RenderEvent {
  const RenderFailed(this.message);
  final String message;
}

class RenderCanceled extends RenderEvent {
  const RenderCanceled();
}

/// Android video rendering (see native/RenderEngine.kt). No internet.
class RenderChannel {
  static const _channel = MethodChannel('com.dramaflow.aistudio/render');
  static final _events = StreamController<RenderEvent>.broadcast();
  static bool _wired = false;

  static Stream<RenderEvent> get events {
    if (!_wired) {
      _wired = true;
      _channel.setMethodCallHandler((call) async {
        final a = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
        switch (call.method) {
          case 'renderProgress':
            _events.add(RenderProgress(((a['percent'] as num?) ?? 0).toInt()));
          case 'renderDone':
            _events.add(RenderDone(
              path: a['path'] as String,
              sizeBytes: (a['sizeBytes'] as num).toInt(),
              durationMs: (a['durationMs'] as num).toInt(),
              height: (a['height'] as num).toInt(),
            ));
          case 'renderError':
            _events.add(RenderFailed((a['message'] as String?) ?? 'Render failed'));
          case 'renderCanceled':
            _events.add(const RenderCanceled());
        }
      });
    }
    return _events.stream;
  }

  /// Starts rendering. Throws [PlatformException] with code `low_storage`,
  /// `busy` or `render_failed` when it cannot start.
  static Future<void> start(Map<String, Object?> job) => _channel.invokeMethod('renderStart', {'job': jsonEncode(job)});

  static Future<void> cancel() => _channel.invokeMethod('renderCancel');

  static Future<int> freeBytes() async => (await _channel.invokeMethod<int>('renderFreeBytes')) ?? 0;

  /// Returns the gallery link. Throws code `use_export` on Android 9 and older.
  static Future<String?> saveToGallery(String path, String name) =>
      _channel.invokeMethod<String>('saveToGallery', {'path': path, 'name': name});

  static Future<bool> deleteRender(String path) async => (await _channel.invokeMethod<bool>('deleteRender', {'path': path})) ?? false;

  /// A frame of the original with optional text, saved to Pictures/DramaFlow
  /// (Android 10+). Returns the preview file path and the gallery link (null
  /// on older Android, where only the preview file exists).
  static Future<({String path, String? gallery})> makeThumbnail({
    required String videoUri,
    required int atMs,
    required String text,
    required String name,
  }) async {
    final r = await _channel.invokeMethod<Map>('makeThumbnail', {'videoUri': videoUri, 'atMs': atMs, 'text': text, 'name': name});
    return (path: r!['path'] as String, gallery: r['gallery'] as String?);
  }
}
