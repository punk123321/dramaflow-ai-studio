import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/core/usage_log.dart';

void main() {
  test('counts add up within a day and start again on the next', () {
    var u = const UsageLog();
    u = u.add('2026-11-22', gemini: 3, voices: 3);
    u = u.add('2026-11-22', gemini: 2, asrSeconds: 61);
    expect(u.gemini, 5);
    expect(u.voices, 3);
    expect(u.asrMinutes, 2); // a started minute counts
    final next = u.add('2026-11-23', gemini: 1);
    expect(next.gemini, 1);
    expect(next.asrSeconds, 0);
    expect(u.forDay('2026-11-23').isEmpty, isTrue);
    expect(u.forDay('2026-11-22').gemini, 5);
  });

  test('encode and decode; bad text is an empty log', () {
    final u = const UsageLog(day: '2026-11-22', gemini: 4, asrSeconds: 90, voices: 2);
    final r = UsageLog.decode(u.encode());
    expect((r.day, r.gemini, r.asrSeconds, r.voices), ('2026-11-22', 4, 90, 2));
    expect(UsageLog.decode('x').isEmpty, isTrue);
    expect(UsageLog.decode(null).isEmpty, isTrue);
    expect(UsageLog.decode('{"gemini":-5,"asr":"a"}').gemini, 0);
  });

  test('day key and minutes for the confirmation box', () {
    expect(UsageLog.dayKey(DateTime(2026, 3, 4)), '2026-03-04');
    expect(asrMinutesFor(0), 0);
    expect(asrMinutesFor(60000), 1);
    expect(asrMinutesFor(60001), 2);
    expect(asrMinutesFor(45 * 60000), 45);
  });

  test('summary names the three counts', () {
    final s = const UsageLog(day: 'd', gemini: 2, asrSeconds: 120, voices: 5).summary();
    expect(s, contains('Gemini 2'));
    expect(s, contains('2 မိနစ်'));
    expect(s, contains('အသံ 5'));
  });
}
