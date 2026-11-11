import 'package:aistudio/core/te_ai.dart';
import 'package:aistudio/core/te_compile.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:aistudio/core/transformative_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const good = '''
Here you go:
```json
{"ops":[
 {"tool":"freezeFrame","at":12.5,"hold":3,"note":"key reveal"},
 {"tool":"cropReframe","from":10,"to":15,"zoom":1.6,"cx":0.4,"cy":0.5},
 {"tool":"motionGraphics","kind":"label","from":20,"to":24,"text":"အရေးကြီးတဲ့ အချိန်","x":0.5,"y":0.1},
 {"tool":"motionGraphics","kind":"arrow","from":30,"to":33,"x":0.3,"y":0.6,"angle":45}
]}
```
Hope it helps''';

  test('prompt lists only supported tools, times, the no-evasion rule and subtitles', () {
    final p = buildTePrompt(projectName: 'Drama', sourceMs: 600000, subtitles: '1\n00:00:01,000 --> 00:00:02,000\nhi', instructions: 'be brief');
    expect(p.contains('600 seconds'), isTrue);
    expect(p.contains('freezeFrame'), isTrue);
    expect(p.contains('smartCut'), isTrue);
    expect(p.contains('splitScreen'), isFalse);
    expect(p.contains('watermark'), isTrue);
    expect(p.contains('be brief'), isTrue);
    expect(p.contains('00:00:01,000'), isTrue);
    final only = buildTePrompt(projectName: 'D', sourceMs: 1000, subtitles: '', tools: {TransformTool.freezeFrame});
    expect(only.contains('cropReframe'), isFalse);
    expect(only.contains('freezeFrame'), isTrue);
  });

  test('long subtitles are cut and the prompt says so', () {
    final p = buildTePrompt(projectName: 'D', sourceMs: 1000, subtitles: 'x' * (maxPromptSubtitleChars + 500));
    expect(p.contains('(shortened)'), isTrue);
    expect(p.length < maxPromptSubtitleChars + 3000, isTrue);
  });

  test('a good reply becomes proposed AI operations, never approved', () {
    final r = parseTeReply(good, sourceMs: 600000, idSeed: 7);
    expect(r.error, isNull);
    expect(r.ops.length, 4);
    expect(r.rejected, isEmpty);
    for (final o in r.ops) {
      expect(o.status, OpStatus.proposed);
      expect(o.source, OpSource.ai);
      expect(o.runnable, isFalse);
    }
    expect(r.ops.map((o) => o.id).toSet().length, 4);
    expect(r.ops[0].startMs, 12500);
    expect(r.ops[1].params['zoom'], 1.6);
    // and they compile only after approval
    final plan = TransformativePlan(ops: r.ops);
    expect(compileOps(const [VideoPiece(0, 600000)], plan.ops).applied, isEmpty);
    final approved = plan.setOpStatus(r.ops[0].id, OpStatus.approved);
    expect(compileOps(const [VideoPiece(0, 600000)], approved.ops).applied.length, 1);
  });

  test('a reply without a code fence and a bare list still work', () {
    expect(parseTeReply('{"ops":[{"tool":"freezeFrame","at":1}]}', sourceMs: 5000, idSeed: 1).ops.length, 1);
    expect(parseTeReply('[{"tool":"freezeFrame","at":1}]', sourceMs: 5000, idSeed: 1).ops.length, 1);
  });

  test('unreadable replies give an error and no operations', () {
    expect(parseTeReply('no json here', sourceMs: 1000, idSeed: 1).error, isNotNull);
    expect(parseTeReply('```json\n{bad}\n```', sourceMs: 1000, idSeed: 1).error, isNotNull);
    expect(parseTeReply('{"x":1}', sourceMs: 1000, idSeed: 1).error, isNotNull);
  });

  test('bad suggestions are rejected with a reason, good ones kept', () {
    final r = parseTeReply('''{"ops":[
      {"tool":"splitScreen","from":1,"to":2},
      {"tool":"freezeFrame","at":9999},
      {"tool":"freezeFrame","at":1,"hold":99},
      {"tool":"cropReframe","from":5,"to":2,"zoom":2},
      {"tool":"cropReframe","from":1,"to":2,"zoom":9},
      {"tool":"motionGraphics","kind":"label","from":1,"to":2,"text":""},
      {"tool":"motionGraphics","kind":"hologram","from":1,"to":2},
      "text",
      {"tool":"freezeFrame","at":2,"hold":2}
    ]}''', sourceMs: 60000, idSeed: 1);
    expect(r.ops.length, 1);
    expect(r.ops.single.startMs, 2000);
    expect(r.rejected.length, 8);
    expect(r.rejected.first.contains('splitScreen'), isTrue);
  });

  test('a smartCut suggestion is read as a range and stays proposed', () {
    final r = parseTeReply('{"ops":[{"tool":"smartCut","from":5,"to":9,"note":"slow"}]}', sourceMs: 60000, idSeed: 1);
    expect(r.ops.single.tool, TransformTool.smartCut);
    expect(r.ops.single.startMs, 5000);
    expect(r.ops.single.endMs, 9000);
    expect(r.ops.single.runnable, isFalse);
  });

  test('no more than the limit is taken', () {
    final many = '{"ops":[${List.filled(40, '{"tool":"freezeFrame","at":1}').join(',')}]}';
    final r = parseTeReply(many, sourceMs: 5000, idSeed: 1);
    expect(r.ops.length, maxAiOps);
    expect(r.rejected, isNotEmpty);
  });
}
