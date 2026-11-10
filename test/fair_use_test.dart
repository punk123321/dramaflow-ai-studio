import 'package:aistudio/core/fair_use.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

VoiceItem v(int off, int dur) => VoiceItem(source: 'a', label: 'a', durationMs: dur, offsetMs: off);

void main() {
  test('measure: overlaps counted once, narration share, longest bare stretch', () {
    final t = Timeline(
      pieces: const [VideoPiece(0, 60000), VideoPiece(30000, 90000)],
      voices: [v(0, 20000), v(10000, 20000), v(100000, 20000)],
    );
    final m = measure(t, sourceMs: 180000);
    expect(m.outputMs, 120000);
    expect(m.reusedMs, 90000);
    expect(m.reusedShare, 0.5);
    expect(m.narrationMs, 50000); // 0-30s and 100-120s
    expect(m.longestBareMs, 70000);
  });

  test('no narration is high risk', () {
    final t = const Timeline(pieces: [VideoPiece(0, 60000)]);
    final r = evaluate(t, const FairUseRecord(), sourceMs: 600000);
    expect(r.risk, Risk.high);
  });

  test('good edit with full record is low risk', () {
    final t = Timeline(pieces: const [VideoPiece(0, 100000)], voices: [v(0, 90000)]);
    final rec = FairUseRecord(
      sourceNote: 'x',
      permission: Permission.granted,
      permissionNote: 'mail 2026-01-01',
      checks: {for (final c in fairUseChecklist) c.key: true},
    );
    final r = evaluate(t, rec, sourceMs: 1000000);
    expect(r.findings, isEmpty);
    expect(r.risk, Risk.low);
  });

  test('reusing almost everything is high risk', () {
    final t = Timeline(pieces: const [VideoPiece(0, 95000)], voices: [v(0, 95000)]);
    final r = evaluate(t, const FairUseRecord(), sourceMs: 100000);
    expect(r.risk, Risk.high);
  });

  test('permission claimed without proof is flagged; record round-trips', () {
    final t = Timeline(pieces: const [VideoPiece(0, 10000)], voices: [v(0, 10000)]);
    final rec = const FairUseRecord(permission: Permission.licensed, sourceNote: 's');
    final r = evaluate(t, rec, sourceMs: 1000000);
    expect(r.findings.any((f) => f.message.contains('အထောက်အထား')), isTrue);
    final back = FairUseRecord.decode(rec.copyWith(checks: {'credit': true}).encode());
    expect(back.permission, Permission.licensed);
    expect(back.checked('credit'), isTrue);
    expect(FairUseRecord.decode('garbage').permission, Permission.none);
  });

  test('upload note states only given facts', () {
    final s = uploadNote(const FairUseRecord(rightsHolder: 'ABC'), dramaTitle: 'Drama');
    expect(s.contains('ABC'), isTrue);
    expect(s.contains('ခွင့်ပြုချက်:'), isFalse);
  });
}
