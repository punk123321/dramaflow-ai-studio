import 'package:flutter_test/flutter_test.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:aistudio/core/voice_fit.dart';

VoiceItem v(int dur) => VoiceItem(source: 'x', label: 'v', durationMs: dur, offsetMs: 0);

void main() {
  test('piece length follows narration and voices start at their pieces', () {
    final tl = Timeline(
      pieces: const [VideoPiece(0, 10000), VideoPiece(20000, 25000)],
      voices: [v(6000), v(8000)],
    );
    final r = fitVideoToVoices(tl, sourceMs: 60000);
    expect(r.fitted, 2);
    expect(r.timeline.pieces[0].lengthMs, 6000);
    expect(r.timeline.pieces[1].startMs, 20000);
    expect(r.timeline.pieces[1].lengthMs, 8000);
    expect(r.timeline.voices[0].offsetMs, 0);
    expect(r.timeline.voices[1].offsetMs, 6000);
    expect(r.notes, isEmpty);
  });

  test('video shorter than narration is reported', () {
    final tl = Timeline(pieces: const [VideoPiece(50000, 55000)], voices: [v(20000)]);
    final r = fitVideoToVoices(tl, sourceMs: 60000);
    expect(r.timeline.pieces[0].endMs, 60000);
    expect(r.notes.single, contains('တိုနေ'));
  });

  test('extra voices or pieces are reported, not lost', () {
    final r1 = fitVideoToVoices(Timeline(pieces: const [VideoPiece(0, 5000)], voices: [v(3000), v(4000)]), sourceMs: 60000);
    expect(r1.timeline.voices.length, 2);
    expect(r1.timeline.voices[1].offsetMs, 3000);
    expect(r1.notes, isNotEmpty);
    final r2 = fitVideoToVoices(Timeline(pieces: const [VideoPiece(0, 5000), VideoPiece(9000, 12000)], voices: [v(3000)]), sourceMs: 60000);
    expect(r2.timeline.pieces[1].lengthMs, 3000);
    expect(r2.notes, isNotEmpty);
  });

  test('zoom is kept', () {
    final tl = Timeline(pieces: const [VideoPiece(0, 9000, ZoomMode.values.last)], voices: [v(4000)]);
    final r = fitVideoToVoices(tl, sourceMs: 60000);
    expect(r.timeline.pieces[0].zoom, ZoomMode.values.last);
  });
}
