import 'package:flutter/material.dart';

/// The six guided-workflow stages, in order. Each keeps one color everywhere.
enum Stage { index, copy, tts, edit, render, save }

extension StageInfo on Stage {
  String get title => const [
        'Video index',
        'Save and copy',
        'TTS / mp3',
        'Studio editor',
        'Render',
        'Save',
      ][index];

  String get subtitle => const [
        'အပိုင်းတွေ ခွဲပြီး index ဖြစ်မယ်',
        'AI ဖိုင် သိမ်း + Prompt ကူး',
        'AI အဖြေ ထည့်ပြီး အသံထုတ်',
        'Clip တွေ ကြည့်ပြီး ပြင်မယ်',
        'Video ထုတ်မယ်',
        'Gallery ထဲ သိမ်းမယ်',
      ][index];

  /// Development phase in which this stage's real function is built.
  int get phase => const [2, 3, 5, 6, 7, 7][index];

  Color get color => const [
        Color(0xFFFF9F43),
        Color(0xFF3DDC84),
        Color(0xFF5B8CFF),
        Color(0xFFA46BFF),
        Color(0xFFF2C94C),
        Color(0xFFFF5FA8),
      ][index];
}
