import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/scenes.dart';

/// One analysed stretch: sample times and the difference to the previous sample.
class FrameSamples {
  const FrameSamples(this.timesMs, this.sigs);
  final List<int> timesMs;
  final Uint8List sigs;
}

class SheetResult {
  const SheetResult(this.path, this.gallery);

  /// Picture in the app cache (for the preview).
  final String path;

  /// Gallery link used for sharing; null on Android 9 and older.
  final String? gallery;
}

/// Scene Recap native helpers (native/SceneTools.kt). The video is only read.
class SceneChannel {
  static const _ch = MethodChannel('com.dramaflow.aistudio/scenes');

  static Future<FrameSamples> analyze(String uri, int fromMs, int toMs, int stepMs) async {
    final r = await _ch.invokeMapMethod<String, Object?>('analyzeFrames', {'uri': uri, 'fromMs': fromMs, 'toMs': toMs, 'stepMs': stepMs});
    final times = [for (final t in (r?['times'] as List? ?? const [])) (t as num).toInt()];
    final sig = r?['sig'];
    final bytes = sig is Uint8List ? sig : Uint8List(0);
    if (bytes.length != times.length * sigBytes) throw StateError('Unexpected frame data');
    return FrameSamples(times, bytes);
  }

  static Future<SheetResult> contactSheet(String uri, List<SceneSpan> scenes, int firstNumber, String name, {int cols = 4, bool toGallery = true}) async {
    final r = await _ch.invokeMapMethod<String, Object?>('contactSheet', {
      'uri': uri,
      'name': name,
      'cols': cols,
      'gallery': toGallery,
      'items': [
        for (var i = 0; i < scenes.length; i++) {'n': firstNumber + i, 'atMs': scenes[i].keyMs},
      ],
    });
    return SheetResult(r?['path'] as String, r?['gallery'] as String?);
  }

  /// 'gemini', 'chooser' or 'no_uri'.
  static Future<String> shareImage(String? gallery, String text) async => (await _ch.invokeMethod<String>('shareImage', {'gallery': gallery, 'text': text})) ?? 'chooser';
}
