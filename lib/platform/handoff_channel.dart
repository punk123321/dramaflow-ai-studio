import 'package:flutter/services.dart';

/// A text file picked from the phone.
class PickedText {
  const PickedText(this.name, this.text);

  final String name;
  final String text;
}

/// How [HandoffChannel.share] delivered the text.
enum ShareResult { gemini, chooser, tooLarge }

/// Android sharing and text-file import/export (see native/MainActivity.kt).
/// There is no Gemini API here: the text is handed to the Gemini app through
/// the normal Android share mechanism, and the user brings the answer back by
/// copy and paste or by importing a file.
class HandoffChannel {
  static const _channel = MethodChannel('com.dramaflow.aistudio/media');

  static Future<ShareResult> share(String text, {bool gemini = true}) async {
    final r = await _channel.invokeMethod<String>('shareText', {'text': text, 'gemini': gemini});
    switch (r) {
      case 'gemini':
        return ShareResult.gemini;
      case 'too_large':
        return ShareResult.tooLarge;
      default:
        return ShareResult.chooser;
    }
  }

  /// Opens an http(s) address in the phone's browser. False when it cannot.
  static Future<bool> openUrl(String url) async => (await _channel.invokeMethod<bool>('openUrl', {'url': url})) ?? false;

  /// Returns null when the user cancels. Throws [PlatformException] when the
  /// file cannot be read.
  static Future<PickedText?> pickTextFile() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('pickTextFile');
    if (raw == null) return null;
    return PickedText((raw['name'] as String?) ?? 'file.txt', (raw['text'] as String?) ?? '');
  }

  /// Returns true when saved, null when the user cancels.
  static Future<bool?> saveTextFile(String name, String text) {
    return _channel.invokeMethod<bool>('saveTextFile', {'name': name, 'text': text});
  }
}
