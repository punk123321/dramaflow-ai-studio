import 'package:flutter/services.dart';

import '../data/video_info.dart';

/// Talks to MainActivity.kt (see native/MainActivity.kt).
class VideoImport {
  static const _channel = MethodChannel('com.dramaflow.aistudio/media');

  /// Opens the Android file picker for videos.
  /// Returns null when the user cancels. Throws [PlatformException] when the
  /// chosen video cannot be read.
  static Future<VideoInfo?> pick() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('pickVideo');
    if (raw == null) return null;
    return VideoInfo.fromMap(raw);
  }
}
