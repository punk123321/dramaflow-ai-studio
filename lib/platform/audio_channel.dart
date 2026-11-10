import 'dart:async';

import 'package:flutter/services.dart';

class TtsStatus {
  const TtsStatus({required this.engineReady, required this.burmese, this.engine});

  final bool engineReady;

  /// True when the phone's text-to-speech engine has a Burmese voice.
  final bool burmese;
  final String? engine;
}

/// A finished piece of audio produced or picked on the phone.
class AudioFile {
  const AudioFile({required this.source, required this.durationMs, required this.sizeBytes, this.name = ''});

  final String source;
  final int durationMs;
  final int sizeBytes;
  final String name;
}

/// Android text-to-speech, microphone, playback and audio import (see
/// native/MainActivity.kt). No internet and no API are involved here.
class AudioChannel {
  static const _channel = MethodChannel('com.dramaflow.aistudio/media');
  static final _ended = StreamController<void>.broadcast();
  static bool _wired = false;

  /// Fires when playback reaches the end or fails.
  static Stream<void> get playbackEnded {
    if (!_wired) {
      _wired = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'playbackEnded') _ended.add(null);
      });
    }
    return _ended.stream;
  }

  static Future<TtsStatus> ttsStatus() async {
    final r = await _channel.invokeMapMethod<String, Object?>('ttsStatus');
    return TtsStatus(
      engineReady: (r?['engineReady'] as bool?) ?? false,
      burmese: (r?['burmese'] as bool?) ?? false,
      engine: r?['engine'] as String?,
    );
  }

  static Future<AudioFile> synthesize(String text, String name, {double rate = 1.0, double pitch = 1.0}) async {
    final r = await _channel.invokeMapMethod<String, Object?>(
      'ttsSynthesize',
      {'text': text, 'name': name, 'rate': rate, 'pitch': pitch},
    );
    return _file(r!);
  }

  /// Null when the user cancels.
  static Future<AudioFile?> pickAudio() async {
    final r = await _channel.invokeMapMethod<String, Object?>('pickAudio');
    if (r == null) return null;
    return AudioFile(
      source: r['source'] as String,
      durationMs: (r['durationMs'] as num).toInt(),
      sizeBytes: (r['sizeBytes'] as num?)?.toInt() ?? 0,
      name: (r['name'] as String?) ?? '',
    );
  }

  /// Picks a picture (for a logo). A small copy is kept inside the app and its
  /// path is returned. Null when the user cancels.
  static Future<String?> pickImage() => _channel.invokeMethod<String>('pickImage');

  static Future<void> play(String source) => _channel.invokeMethod('playAudio', {'source': source});

  static Future<void> stop() => _channel.invokeMethod('stopAudio');

  static Future<void> recordStart(String name) => _channel.invokeMethod('recordStart', {'name': name});

  static Future<AudioFile> recordStop() async {
    final r = await _channel.invokeMapMethod<String, Object?>('recordStop');
    return _file(r!);
  }

  /// Returns true when saved, null when the user cancels.
  static Future<bool?> export(String path, String name, String mime) =>
      _channel.invokeMethod<bool>('exportFile', {'path': path, 'name': name, 'mime': mime});

  static Future<void> deleteFile(String path) => _channel.invokeMethod('deleteFile', {'path': path});

  static AudioFile _file(Map<String, Object?> r) => AudioFile(
        source: r['path'] as String,
        durationMs: (r['durationMs'] as num).toInt(),
        sizeBytes: (r['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}
