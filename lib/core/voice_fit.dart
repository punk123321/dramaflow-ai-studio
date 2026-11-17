import 'timeline.dart';

/// Result of [fitVideoToVoices].
class VoiceFitResult {
  const VoiceFitResult(this.timeline, this.notes, this.fitted);
  final Timeline timeline;

  /// Plain Burmese warnings for the user.
  final List<String> notes;

  /// How many piece/voice pairs were matched.
  final int fitted;
}

/// Matches video piece N with narration N (in order). Each piece gets the
/// length of its narration (plus [gapMs]) by moving the END of the piece in the
/// original video, and the narration starts exactly where its piece starts on
/// the output. Subtitles follow the pieces by themselves.
///
/// The original video is never changed; only the saved plan is. When the
/// original video ends before a narration does, the piece is stopped at the end
/// of the video and a note says so.
VoiceFitResult fitVideoToVoices(Timeline tl, {required int sourceMs, int gapMs = 0}) {
  final voices = [...tl.voices]..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
  final pieces = [...tl.pieces];
  final notes = <String>[];
  final n = pieces.length < voices.length ? pieces.length : voices.length;
  final outVoices = <VoiceItem>[];
  var t = 0;
  var voiceEnd = 0;
  for (var i = 0; i < pieces.length; i++) {
    var p = pieces[i];
    if (i < n && !p.freeze) {
      final v = voices[i];
      final wanted = v.durationMs + (gapMs < 0 ? 0 : gapMs);
      var end = p.startMs + wanted;
      if (sourceMs > 0 && end > sourceMs) {
        final lack = end - sourceMs;
        end = sourceMs;
        notes.add('အပိုင်း ${i + 1}: ဗီဒီယိုက အသံထက် ${(lack / 1000).toStringAsFixed(1)} စက္ကန့် တိုနေတယ်။ အပိုင်းကို ဗီဒီယိုအဆုံးထိ ထားပြီး။');
      }
      if (end <= p.startMs) {
        end = p.startMs + 500;
        if (sourceMs > 0 && end > sourceMs) end = sourceMs;
      }
      if (end > p.startMs) p = p.withRange(p.startMs, end);
      pieces[i] = p;
      final off = t > voiceEnd ? t : voiceEnd;
      outVoices.add(v.copyWith(offsetMs: off));
      voiceEnd = off + v.durationMs;
    }
    t += p.lengthMs;
  }
  for (var i = n; i < voices.length; i++) {
    final off = voiceEnd;
    outVoices.add(voices[i].copyWith(offsetMs: off));
    voiceEnd = off + voices[i].durationMs;
  }
  if (voices.length > pieces.length) {
    notes.add('အသံ ${voices.length - pieces.length} ခုအတွက် ဗီဒီယိုအပိုင်း မရှိဘူး။ အပိုင်းထပ်ထည့်ပါ။');
  }
  if (pieces.length > voices.length) {
    notes.add('ဗီဒီယိုအပိုင်း ${pieces.length - voices.length} ခုမှာ အသံမရှိဘူး (မပြောင်းထားဘူး)။');
  }
  return VoiceFitResult(tl.copyWith(pieces: pieces, voices: outVoices), notes, n);
}
